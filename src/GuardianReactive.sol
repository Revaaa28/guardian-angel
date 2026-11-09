// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title GuardianReactive
/// @notice The always-on watchdog, deployed on Reactive Lasna. It subscribes to GTT `Transfer`
///         events sent FROM a GuardianVault on Base Sepolia. Any single outbound transfer above
///         the owner's cap — that is not destined for the cold address itself — triggers a
///         callback ordering the vault to freeze and sweep everything to the cold address.
/// @dev `react()` NEVER reverts: a reverting reactive contract is still billed in full, so every
///      non-actionable log falls through silently. All timing uses `block.timestamp` (Base
///      Sepolia produces 200 ms blocks; block-count timers are forbidden by the buildathon
///      ground rules). The subscription is created by `watch()` after deployment rather than in
///      the constructor: the subscription's topic1 is the vault's address, and the vault itself
///      needs this contract's address first (its callback sender is immutable).
contract GuardianReactive is AbstractReactive {
    /// @notice Origin and destination chain: Base Sepolia.
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;

    /// @notice Callback gas limit. Requests below 100,000 are ignored by the network; the
    ///         proxy also withholds its own overhead, so follow the docs and use 1,000,000.
    uint64 internal constant CALLBACK_GAS_LIMIT = 1_000_000;

    /// @notice topic0 of ERC-20 `Transfer(address,address,uint256)`.
    bytes32 internal constant TRANSFER_TOPIC0 = keccak256("Transfer(address,address,uint256)");

    /// @notice The contract's owner (deployer). Only the owner configures the guardian.
    address public immutable owner;

    /// @notice Address that receives the sweep; transfers TO it never trigger the guardian
    ///         (this is what stops the vault's own sweep from re-triggering the guardian).
    address public immutable coldAddress;

    /// @notice Single-transfer cap in GTT wei. Transfers strictly above it trigger.
    uint256 public cap;

    /// @notice Minimum seconds between two triggers.
    uint256 public cooldown;

    /// @notice The GuardianVault on Base Sepolia that receives callbacks (set post-deploy).
    address public destination;

    /// @notice The token / vault pair currently watched (set by `watch()`).
    address public watchedToken;
    address public watchedVault;

    /// @notice Timestamp of the last trigger.
    uint256 public lastTrigger;

    error NotOwner();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param cap_ Single-transfer cap in GTT wei.
    /// @param coldAddress_ The owner's cold address.
    /// @param cooldown_ Minimum seconds between triggers.
    constructor(uint256 cap_, address coldAddress_, uint256 cooldown_) payable {
        if (coldAddress_ == address(0)) revert ZeroAddress();
        owner = msg.sender;
        cap = cap_;
        coldAddress = coldAddress_;
        cooldown = cooldown_;
    }

    /// @notice Updates the single-transfer cap. Owner only.
    function setCap(uint256 cap_) external onlyOwner {
        cap = cap_;
    }

    /// @notice Updates the cooldown between triggers. Owner only.
    function setCooldown(uint256 cooldown_) external onlyOwner {
        cooldown = cooldown_;
    }

    /// @notice Sets the callback recipient (the GuardianVault on Base Sepolia). Owner only.
    /// @dev Deployment order is forced by the vault's immutable callback sender: deploy this
    ///      contract first, then the vault, then call this setter.
    function setDestination(address vault_) external onlyOwner {
        if (vault_ == address(0)) revert ZeroAddress();
        destination = vault_;
    }

    /// @notice Subscribes to outbound GTT transfers from `vault_` on Base Sepolia. Owner only.
    /// @dev Watches topic1 == the vault's address, i.e. only transfers SENT BY the vault.
    ///      The vault's own sweep goes to the cold address and is filtered out in `react()`.
    function watch(address token_, address vault_) external onlyOwner {
        if (token_ == address(0) || vault_ == address(0)) revert ZeroAddress();
        watchedToken = token_;
        watchedVault = vault_;
        SYSTEM.subscribe(
            BASE_SEPOLIA_CHAIN_ID,
            token_,
            uint256(TRANSFER_TOPIC0),
            uint256(uint160(vault_)),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external override onlySystem {
        // A Transfer log carries exactly 3 topics (signature, from, to). Anything with fewer
        // cannot carry a recipient, so it cannot be acted on.
        if (log_.opCode < 3) return;
        // The non-indexed payload of a Transfer is a single uint256. Guard the decode so a
        // malformed record can never make this function revert (reverts are still billed).
        if (log_.data.length < 32) return;
        uint256 value = abi.decode(log_.data, (uint256));
        // At or below the cap is ordinary spending.
        if (value <= cap) return;
        // The vault's own sweep lands here (recipient == cold address): never re-trigger.
        address recipient = address(uint160(log_.topic2));
        if (recipient == coldAddress) return;
        // One trigger per cooldown window.
        if (block.timestamp < lastTrigger + cooldown) return;
        // Not wired yet: nowhere legitimate to send the callback.
        if (destination == address(0)) return;

        lastTrigger = block.timestamp;

        // The first payload argument is the address(0) placeholder: the callback proxy
        // overwrites it with this contract's address, which is how the vault authenticates.
        bytes memory payload = abi.encodeWithSignature(
            "freezeAndSweep(address,uint256,uint256)", address(0), value, block.timestamp
        );

        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: BASE_SEPOLIA_CHAIN_ID,
                recipient: destination,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }

    /// @notice Settles any outstanding debt from this contract's own balance (the system
    ///         contract bills this contract, in lREACT, per reactive transaction).
    function coverDebt() external {
        _coverDebt();
    }

    // Native funding for reactive-transaction fees arrives through the payable
    // `receive()` inherited from AbstractPayer.
}
