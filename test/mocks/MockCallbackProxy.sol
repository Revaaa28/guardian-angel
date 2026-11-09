// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

/// @notice Test double for the Base Sepolia callback proxy.
/// @dev In tests the runtime code of this contract is etched onto the real proxy address
///      (0x476F44b11F5C942c58f4c8E3d0300E5710743585) so that the vault's `pay()` / `coverDebt()`
///      path and its `debt()` reads behave as they would against the real proxy. Delivery of a
///      callback itself is simulated by pranking that address.
contract MockCallbackProxy {
    mapping(address => uint256) public debtOf;

    function debt(address contract_) external view returns (uint256) {
        return debtOf[contract_];
    }

    function setDebt(address contract_, uint256 amount_) external {
        debtOf[contract_] = amount_;
    }

    receive() external payable { }
}
