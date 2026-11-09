// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";

import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";

import { GuardianReactive } from "../src/GuardianReactive.sol";
import { GuardianVault } from "../src/GuardianVault.sol";
import { GuardianToken } from "../src/GuardianToken.sol";
import { MockSystemContract } from "./mocks/MockSystemContract.sol";

contract GuardianReactiveTest is Test {
    address internal constant SYSTEM_ADDRESS = 0x8888888888888888888888888888888888888888;
    uint256 internal constant REACTIVE_IGNORE =
        0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
    uint256 internal constant BASE_SEPOLIA = 84532;

    uint256 internal constant CAP = 100 ether;
    uint256 internal constant COOLDOWN = 3600;
    uint256 internal constant START_TIME = 10_000;

    address internal cold = makeAddr("cold");
    address internal stranger = makeAddr("stranger");

    MockSystemContract internal systemMock;
    GuardianToken internal token;
    GuardianReactive internal reactive;
    GuardianVault internal vault;

    function setUp() public {
        // AbstractReactive.SYSTEM is hardcoded to 0x8888...8888: etch the mock's code there.
        MockSystemContract deployed = new MockSystemContract();
        vm.etch(SYSTEM_ADDRESS, address(deployed).code);
        systemMock = MockSystemContract(payable(SYSTEM_ADDRESS));

        token = new GuardianToken();
        reactive = new GuardianReactive(CAP, cold, COOLDOWN);
        vault = new GuardianVault(address(token), cold, address(reactive));
        reactive.setDestination(address(vault));
        reactive.watch(address(token), address(vault));

        vm.warp(START_TIME);
    }

    // ---------- watch() ----------

    function testWatchSubscribesWithExactSixArgs() public view {
        assertEq(systemMock.subscribeCount(), 1);
        (
            uint256 chainId,
            address contract_,
            uint256 topic0,
            uint256 topic1,
            uint256 topic2,
            uint256 topic3
        ) = systemMock.lastSubscription();
        assertEq(chainId, BASE_SEPOLIA);
        assertEq(contract_, address(token));
        assertEq(topic0, uint256(keccak256("Transfer(address,address,uint256)")));
        assertEq(topic1, uint256(uint160(address(vault))));
        assertEq(topic2, REACTIVE_IGNORE);
        assertEq(topic3, REACTIVE_IGNORE);
        assertEq(reactive.watchedToken(), address(token));
        assertEq(reactive.watchedVault(), address(vault));
    }

    // ---------- react(): fall-through cases ----------

    function testReactIgnoresBelowCapTransfer() public {
        _react(_log(stranger, CAP - 1, 3));
        _react(_log(stranger, CAP, 3)); // exactly at the cap is still ordinary spending
        assertEq(systemMock.callbackCount(), 0);
        assertEq(reactive.lastTrigger(), 0);
    }

    function testReactIgnoresTransferToColdAddress() public {
        // The vault's own sweep lands here; it must never re-trigger the guardian.
        _react(_log(cold, CAP * 10, 3));
        assertEq(systemMock.callbackCount(), 0);
    }

    function testReactIgnoresLogWithTooFewTopics() public {
        _react(_log(stranger, CAP * 10, 2));
        assertEq(systemMock.callbackCount(), 0);
    }

    function testReactIgnoresSecondBreachInsideCooldown() public {
        _react(_log(stranger, CAP * 2, 3));
        assertEq(systemMock.callbackCount(), 1);

        _react(_log(stranger, CAP * 2, 3));
        assertEq(systemMock.callbackCount(), 1);

        vm.warp(START_TIME + COOLDOWN - 1);
        _react(_log(stranger, CAP * 2, 3));
        assertEq(systemMock.callbackCount(), 1);

        vm.warp(START_TIME + COOLDOWN);
        _react(_log(stranger, CAP * 2, 3));
        assertEq(systemMock.callbackCount(), 2);
    }

    // ---------- react(): the breach ----------

    function testReactBreachRequestsExactlyOneCallback() public {
        uint256 breach = 150 ether;
        _react(_log(stranger, breach, 3));

        assertEq(systemMock.callbackCount(), 1);
        assertEq(systemMock.lastCallbackChainId(), BASE_SEPOLIA);
        assertEq(systemMock.lastCallbackRecipient(), address(vault));
        assertEq(systemMock.lastCallbackGasLimit(), 1_000_000);
        assertEq(reactive.lastTrigger(), START_TIME);

        bytes memory payload = systemMock.lastCallbackPayload();
        bytes4 selector;
        assembly {
            selector := mload(add(payload, 32))
        }
        assertEq(selector, GuardianVault.freezeAndSweep.selector);

        (address injected, uint256 amount, uint256 ts) =
            abi.decode(_stripSelector(payload), (address, uint256, uint256));
        assertEq(injected, address(0)); // placeholder the proxy overwrites
        assertEq(amount, breach);
        assertEq(ts, START_TIME);
    }

    function testReactRevertsForNonSystemCaller() public {
        vm.expectRevert(
            abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), SYSTEM_ADDRESS)
        );
        reactive.react(_log(stranger, CAP * 2, 3));
    }

    // ---------- configuration & payer pattern ----------

    function testOwnerSetters() public {
        reactive.setCap(250 ether);
        reactive.setCooldown(60);
        assertEq(reactive.cap(), 250 ether);
        assertEq(reactive.cooldown(), 60);

        vm.prank(stranger);
        vm.expectRevert(GuardianReactive.NotOwner.selector);
        reactive.setCap(1);
    }

    function testCoverDebt() public {
        systemMock.setDebt(address(reactive), 0.25 ether);
        vm.deal(address(reactive), 1 ether);
        reactive.coverDebt();
        assertEq(SYSTEM_ADDRESS.balance, 0.25 ether);
        assertEq(address(reactive).balance, 0.75 ether);
    }

    // ---------- helpers ----------

    function _log(address to_, uint256 value_, uint256 opCode_)
        internal
        view
        returns (IReactive.LogRecord memory)
    {
        return IReactive.LogRecord({
            chainId: BASE_SEPOLIA,
            contractAddress: address(token),
            topic0: uint256(keccak256("Transfer(address,address,uint256)")),
            topic1: uint256(uint160(address(vault))),
            topic2: uint256(uint160(to_)),
            topic3: 0,
            data: abi.encode(value_),
            blockNumber: 1,
            opCode: opCode_,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
    }

    function _react(IReactive.LogRecord memory log_) internal {
        vm.prank(SYSTEM_ADDRESS);
        reactive.react(log_);
    }

    function _stripSelector(bytes memory data_) internal pure returns (bytes memory) {
        bytes memory args = new bytes(data_.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = data_[i + 4];
        }
        return args;
    }
}
