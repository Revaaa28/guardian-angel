// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

import { GuardianToken } from "./GuardianToken.sol";

/// @title GuardianVault
/// @notice Holds the owner's GTT on Base Sepolia. When the GuardianReactive contract (on Lasna)
///         reports an outbound transfer above the owner's cap, this vault receives a callback
///         through the Base Sepolia callback proxy, freezes itself, and sweeps its entire
///         remaining GTT balance to the owner's cold address.
/// @dev Callback authentication follows the Reactive Callback Contracts docs exactly: the method
///      is guarded by `onlyServiceProvider` (msg.sender must be the callback proxy) and
///      `onlyCallbackSender` (the payload's first address — injected by the proxy — must be the
///      authorized reactive contract). Both the proxy and the reactive contract address are
///      immutable, so a wrong reactive address at deployment means redeploying this vault.
contract GuardianVault is AbstractCallback {
    /// @notice Base Sepolia callback proxy (Reactive "Origins & Destinations" table).
    address internal constant BASE_SEPOLIA_CALLBACK_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;

    /// @notice The token this vault protects.
    GuardianToken public immutable token;

    /// @notice Where the entire remaining balance is swept when the guardian triggers.
    address public immutable coldAddress;

    /// @notice The vault's owner (deployer). Only the owner can withdraw or unfreeze.
    address public immutable owner;

    /// @notice True once the guardian has triggered, until the owner unfreezes.
    bool public frozen;

    /// @notice Emitted when the guardian callback fires.
    /// @param amount_ The breaching transfer amount reported by the reactive contract.
    /// @param ts_ The timestamp (on Reactive Network) at which the breach was detected.
    /// @param sweptAmount_ The amount of GTT swept to the cold address by this call.
    event GuardianTriggered(uint256 amount_, uint256 ts_, uint256 sweptAmount_);

    event Deposited(address indexed from_, uint256 amount_);
    event Withdrawn(address indexed to_, uint256 amount_);

    error NotOwner();
    error Frozen();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param token_ The GTT token contract.
    /// @param coldAddress_ The owner's cold address; receives the sweep.
    /// @param reactive_ The GuardianReactive contract on Lasna, authorized to trigger callbacks.
    constructor(address token_, address coldAddress_, address reactive_)
        payable
        AbstractCallback(IPayable(payable(BASE_SEPOLIA_CALLBACK_PROXY)), reactive_)
    {
        if (token_ == address(0) || coldAddress_ == address(0) || reactive_ == address(0)) {
            revert ZeroAddress();
        }
        token = GuardianToken(token_);
        coldAddress = coldAddress_;
        owner = msg.sender;
    }

    /// @notice Deposits GTT into the vault (pulled from the caller via transferFrom).
    function deposit(uint256 amount_) external {
        token.transferFrom(msg.sender, address(this), amount_);
        emit Deposited(msg.sender, amount_);
    }

    /// @notice Withdraws GTT to `to_`. Owner only, and blocked while frozen.
    function withdraw(address to_, uint256 amount_) external onlyOwner {
        if (frozen) revert Frozen();
        if (to_ == address(0)) revert ZeroAddress();
        token.transfer(to_, amount_);
        emit Withdrawn(to_, amount_);
    }

    /// @notice Guardian callback: freezes the vault and sweeps the full remaining GTT balance
    ///         to the cold address. Callable only by the Base Sepolia callback proxy carrying
    ///         a payload authorized by the GuardianReactive contract.
    /// @param reactive_ Injected by the proxy: the reactive contract that requested the callback.
    /// @param amount_ The breaching transfer amount.
    /// @param ts_ The timestamp at which the reactive contract detected the breach.
    function freezeAndSweep(address reactive_, uint256 amount_, uint256 ts_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        frozen = true;
        uint256 sweptAmount = token.balanceOf(address(this));
        if (sweptAmount > 0) {
            token.transfer(coldAddress, sweptAmount);
        }
        emit GuardianTriggered(amount_, ts_, sweptAmount);
    }

    /// @notice Lifts the freeze. Owner only.
    function unfreeze() external onlyOwner {
        frozen = false;
    }

    /// @notice Settles any outstanding callback debt from this contract's own balance
    ///         (the callback proxy bills this contract, in Base Sepolia ETH, per delivery).
    function coverDebt() external {
        _coverDebt();
    }

    // Native funding for callback fees arrives through the payable `receive()`
    // inherited from AbstractPayer.
}
