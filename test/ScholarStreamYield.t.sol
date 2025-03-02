// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ScholarStreamYield} from "../src/ScholarStreamYield.sol";
import {MockYieldVault} from "./mocks/MockYieldVault.sol";
import {MockToken} from "./mocks/MockToken.sol";

contract StreamYieldTest is Test {
    ScholarStreamYield scholar;
    MockYieldVault vault;
    MockToken token;
    address payer;
    address payee;

    function setUp() public {
        token = new MockToken("USDC", 6);
        vault = new MockYieldVault(address(token));
        scholar = new ScholarStreamYield(address(token), address(vault));
        payer = vm.addr(1);
        payee = vm.addr(2);
        token.mint(payer, 10_000 * 1e6);
        vm.startPrank(payer);
        token.approve(address(scholar), 10_000 * 1e6);
        vm.stopPrank();
    }

    function testDeposit() public {
        uint256 depositAmount = 1_000 * 1e6;
        vm.prank(payer);
        scholar.deposit(depositAmount);
        uint256 principal = scholar.balances(payer);
        assertEq(principal, depositAmount, "Principal not recorded correctly");
        uint256 vaultBalance = token.balanceOf(address(vault));
        assertEq(vaultBalance, depositAmount, "Vault did not receive the deposit");
    }

    function testStreamingAndPayeeWithdrawal() public {
        uint256 depositAmount = 1_000 * 1e6;
        uint256 streamRate = 10 * 1e6;
        vm.prank(payer);
        scholar.deposit(depositAmount);
        vm.prank(payer);
        scholar.createStream(payee, streamRate);
        vm.warp(block.timestamp + 100);
        vm.prank(payee);
        scholar.withdraw(payer, payee, streamRate);
        uint256 expected = 100 * streamRate;
        uint256 payeeBalance = token.balanceOf(payee);
        assertEq(payeeBalance, expected, "Incorrect payee withdrawal amount");
        uint256 remainingPrincipal = scholar.balances(payer);
        assertEq(remainingPrincipal, depositAmount - expected, "Principal not reduced correctly");
    }

    function testPayerWithdrawal() public {
        uint256 depositAmount = 2_000 * 1e6;
        uint256 streamRate = 5 * 1e6;
        vm.prank(payer);
        scholar.deposit(depositAmount);
        vm.prank(payer);
        scholar.createStream(payee, streamRate);
        vm.warp(block.timestamp + 100);
        vm.prank(payee);
        scholar.withdraw(payer, payee, streamRate);
        uint256 streamed = 100 * streamRate;
        uint256 remaining = scholar.balances(payer);
        assertEq(remaining, depositAmount - streamed, "Incorrect remaining principal");
        vm.prank(payer);
        scholar.withdrawPayer(remaining);
        uint256 payerBalance = token.balanceOf(payer);
        assertEq(payerBalance, depositAmount - streamed, "Payer did not receive correct withdrawal amount");
        assertEq(scholar.balances(payer), 0, "Principal not zero after payer withdrawal");
    }

    function testFullFlow() public {
        uint256 depositAmount = 5_000 * 1e6;
        uint256 streamRate = 10 * 1e6;
        vm.prank(payer);
        scholar.deposit(depositAmount);
        console.log("Deposited principal:", scholar.balances(payer));
        vm.prank(payer);
        scholar.createStream(payee, streamRate);
        console.log("Stream created.");
        vm.warp(block.timestamp + 50);
        vm.prank(payee);
        scholar.withdraw(payer, payee, streamRate);
        uint256 firstWithdrawal = 50 * streamRate;
        uint256 payeeBalAfterFirst = token.balanceOf(payee);
        console.log("Payee balance after first withdrawal:", payeeBalAfterFirst);
        assertEq(payeeBalAfterFirst, firstWithdrawal, "First withdrawal amount incorrect");
        vm.warp(block.timestamp + 100);
        vm.prank(payee);
        scholar.withdraw(payer, payee, streamRate);
        uint256 secondWithdrawal = 100 * streamRate;
        uint256 totalPayeeBal = token.balanceOf(payee);
        console.log("Payee balance after second withdrawal:", totalPayeeBal);
        assertEq(totalPayeeBal, firstWithdrawal + secondWithdrawal, "Total payee withdrawal amount incorrect");
        vm.prank(payer);
        scholar.cancelStream(payee, streamRate);
        console.log("Stream cancelled.");
        uint256 expectedStreamed = (50 + 100) * streamRate;
        uint256 remainingPrincipal = scholar.balances(payer);
        console.log("Remaining principal after streamed withdrawals:", remainingPrincipal);
        uint256 expectedRemaining = depositAmount - expectedStreamed;
        assertEq(remainingPrincipal, expectedRemaining, "Remaining principal mismatch after cancellation");
        vm.prank(payer);
        scholar.withdrawPayer(remainingPrincipal);
        uint256 finalPayerBalance = token.balanceOf(payer);
        console.log("Final payer balance after withdrawal:", finalPayerBalance);
        assertEq(finalPayerBalance, expectedRemaining, "Final payer withdrawal amount incorrect");
        assertEq(scholar.balances(payer), 0, "Principal not zero after full flow");
    }
}
