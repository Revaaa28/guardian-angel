// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";

import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

import { GuardianVault } from "../src/GuardianVault.sol";
import { GuardianReactive } from "../src/GuardianReactive.sol";
import { GuardianToken } from "../src/GuardianToken.sol";
import { MockCallbackProxy } from "./mocks/MockCallbackProxy.sol";

contract GuardianVaultTest is Test {
    address internal constant PROXY_ADDRESS = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;

    address internal cold = makeAddr("cold");
    address internal attacker = makeAddr("attacker");
    address internal recipient = makeAddr("recipient");

    GuardianToken internal token;
    GuardianReactive internal reactive;
    GuardianVault internal vault;
    MockCallbackProxy internal proxyMock;

    event GuardianTriggered(uint256 amount_, uint256 ts_, uint256 sweptAmount_);

    function setUp() public {
        // The vault's service provider is the real Base Sepolia proxy address: etch the
        // mock's code there so debt() reads / pay() behave as against the real proxy.
        MockCallbackProxy deployedProxy = new MockCallbackProxy();
        vm.etch(PROXY_ADDRESS, address(deployedProxy).code);
        proxyMock = MockCallbackProxy(payable(PROXY_ADDRESS));

        token = new GuardianToken();
        reactive = new GuardianReactive(100 ether, cold, 3600);
        vault = new GuardianVault(address(token), cold, address(reactive));
    }

    // ---------- funding / withdrawal ----------

    function testDepositAndWithdraw() public {
        _fundVault(500 ether);
        assertEq(token.balanceOf(address(vault)), 500 ether);

        vault.withdraw(recipient, 200 ether);
        assertEq(token.balanceOf(recipient), 200 ether);
        assertEq(token.balanceOf(address(vault)), 300 ether);
    }

    function testWithdrawRevertsForNonOwner() public {
        _fundVault(10 ether);
        vm.prank(attacker);
        vm.expectRevert(GuardianVault.NotOwner.selector);
        vault.withdraw(recipient, 1 ether);
    }

    // ---------- freezeAndSweep authentication ----------

    function testFreezeAndSweepRevertsFromNonProxyCaller() public {
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, attacker, PROXY_ADDRESS)
        );
        vault.freezeAndSweep(address(reactive), 1, 1);
    }

    function testFreezeAndSweepRevertsWithWrongInjectedSender() public {
        // Even through the legitimate proxy, only the authorized reactive contract may drive
        // the callback: the injected first address must equal _CALLBACK_SENDER.
        vm.prank(PROXY_ADDRESS);
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractCallback.CallbackNotAuthorized.selector, attacker, address(reactive)
            )
        );
        vault.freezeAndSweep(attacker, 1, 1);
    }

    // ---------- freezeAndSweep happy path ----------

    function testFreezeAndSweepFreezesAndSweepsEverything() public {
        _fundVault(500 ether);
        uint256 breachAmount = 150 ether;
        uint256 ts = 424_242;

        vm.expectEmit(false, false, false, true, address(vault));
        emit GuardianTriggered(breachAmount, ts, 500 ether);

        vm.prank(PROXY_ADDRESS);
        vault.freezeAndSweep(address(reactive), breachAmount, ts);

        assertTrue(vault.frozen());
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(token.balanceOf(cold), 500 ether);
    }

    function testWithdrawBlockedWhileFrozenAndWorksAfterUnfreeze() public {
        _fundVault(500 ether);

        vm.prank(PROXY_ADDRESS);
        vault.freezeAndSweep(address(reactive), 150 ether, 1);
        assertTrue(vault.frozen());

        vm.expectRevert(GuardianVault.Frozen.selector);
        vault.withdraw(recipient, 1 ether);

        vault.unfreeze();
        assertFalse(vault.frozen());

        _fundVault(50 ether);
        vault.withdraw(recipient, 20 ether);
        assertEq(token.balanceOf(recipient), 20 ether);
        assertEq(token.balanceOf(address(vault)), 30 ether);
    }

    // ---------- payer pattern ----------

    function testCoverDebt() public {
        proxyMock.setDebt(address(vault), 0.3 ether);
        vm.deal(address(vault), 1 ether);
        vault.coverDebt();
        assertEq(PROXY_ADDRESS.balance, 0.3 ether);
        assertEq(address(vault).balance, 0.7 ether);
    }

    // ---------- helpers ----------

    function _fundVault(uint256 amount_) internal {
        token.mint(address(this), amount_);
        token.approve(address(vault), amount_);
        vault.deposit(amount_);
    }
}
