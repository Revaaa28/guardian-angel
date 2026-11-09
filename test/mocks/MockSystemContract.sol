// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";

/// @notice Test double for the Reactive system contract.
/// @dev In tests the runtime code of this contract is etched onto the real system contract
///      address (0x8888888888888888888888888888888888888888), which is the address
///      `AbstractReactive.SYSTEM` points at. It records every subscription and callback
///      request so tests can assert on them, and reports a configurable debt.
contract MockSystemContract {
    struct Subscription {
        uint256 chainId;
        address contract_;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
    }

    uint256 public subscribeCount;
    Subscription public lastSubscription;

    uint256 public callbackCount;
    uint256 public lastCallbackChainId;
    address public lastCallbackRecipient;
    uint64 public lastCallbackGasLimit;
    bytes public lastCallbackPayload;

    mapping(address => uint256) public debtOf;

    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external {
        subscribeCount++;
        lastSubscription = Subscription(chainId_, contract_, topic0_, topic1_, topic2_, topic3_);
    }

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external { }

    function requestCallback(ISystemContract.CallbackVersion, bytes memory) external { }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config_) external {
        callbackCount++;
        lastCallbackChainId = config_.chainId;
        lastCallbackRecipient = config_.recipient;
        lastCallbackGasLimit = config_.gasLimit;
        lastCallbackPayload = config_.payload;
    }

    function debt(address contract_) external view returns (uint256) {
        return debtOf[contract_];
    }

    function setDebt(address contract_, uint256 amount_) external {
        debtOf[contract_] = amount_;
    }

    receive() external payable { }
}
