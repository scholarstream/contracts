// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ScholarStreamYield} from "../src/ScholarStreamYield.sol";
import {MockYieldVault} from "./mocks/MockYieldVault.sol";
import {MockToken} from "./mocks/MockToken.sol";

contract ScholarStreamYieldTest is Test {
    ScholarStreamYield scholar;
    MockYieldVault vault;
    MockToken token;
    address payer;
    address payee;

    function setUp() public {
        // Deploy a mock token (e.g. USDC with 6 decimals)
        token = new MockToken("USDC", 6);
        // Deploy a mock yield vault (which supports simulateYield)
        vault = new MockYieldVault(address(token));
        // Deploy the ScholarStreamYield contract with token and vault addresses
        scholar = new ScholarStreamYield(address(token), address(vault));
        // Set test addresses
        payer = vm.addr(1);
        payee = vm.addr(2);
        // Mint tokens to payer
        token.mint(payer, 10_000 * 1e6);
        // Payer approves ScholarStreamYield to spend tokens
        vm.startPrank(payer);
        token.approve(address(scholar), 10_000 * 1e6);
        vm.stopPrank();
    }

    /// @notice Test deposit: split deposit into vault and direct funds and check effective balance.
    function testDeposit() public {
        uint256 depositAmount = 1_000 * 1e6;
        uint256 percentToVault = 70; // 70% to vault, 30% direct

        vm.prank(payer);
        scholar.deposit(depositAmount, percentToVault);

        // Effective balance should equal deposit amount initially (paidBalance is zero)
        uint256 effectiveBal = scholar.effectiveBalance(payer);
        assertEq(effectiveBal, depositAmount, "Effective balance should equal deposit amount");

        console.log("Effective balance:", effectiveBal);
        console.log("Direct balance:", scholar.directBalances(payer));
        console.log("Vault shares:", scholar.vaultShares(payer));
    }

    /// @notice Test stream creation and that stream start time is recorded.
    function testStreamCreation() public {
        uint256 depositAmount = 1_000 * 1e6;
        uint256 percentToVault = 70;
        uint256 rate = 10 * 1e6; // 10 tokens/sec

        vm.prank(payer);
        scholar.deposit(depositAmount, percentToVault);
        vm.prank(payer);
        scholar.createStream(payee, rate);

        bytes32 streamId = scholar.getStreamId(payer, payee, rate);
        uint256 startTime = scholar.streamToStart(streamId);
        console.log("Stream ID:", uint256(streamId));
        console.log("Stream start time:", startTime);
        assertGt(startTime, 0);
    }

    /// @notice Test first withdrawal from stream after a short period.
    function testWithdrawStreamFirst() public {
        uint256 depositAmount = 1_000 * 1e6;
        uint256 percentToVault = 70;
        uint256 rate = 10 * 1e6; // 10 tokens/sec

        vm.prank(payer);
        scholar.deposit(depositAmount, percentToVault);
        vm.prank(payer);
        scholar.createStream(payee, rate);

        // Warp forward 10 seconds and let payee withdraw streamed funds.
        vm.warp(block.timestamp + 10);
        vm.prank(payee);
        scholar.withdraw(payer, payee, rate);

        // Expected: 10 sec * 10 tokens/sec = 100 * 1e6 tokens.
        uint256 expected = 10 * rate;
        uint256 payeeBalance = token.balanceOf(payee);
        console.log("Payee balance after first withdrawal:", payeeBalance);
        assertEq(payeeBalance, expected, "Incorrect first withdrawal amount");
    }

    /// @notice Test withdrawing stream funds in two steps with a time gap.
    function testWithdrawStreamAfterOneDay() public {
        uint256 depositAmount = 1_000 * 1e6;
        uint256 percentToVault = 70;
        uint256 rate = 2 * 1e6; // 2 tokens/sec

        vm.startPrank(payer);
        scholar.deposit(depositAmount, percentToVault);
        scholar.createStream(payee, rate);
        vm.stopPrank();

        // First withdrawal after 10 seconds.
        vm.warp(block.timestamp + 10);
        vm.prank(payee);
        scholar.withdraw(payer, payee, rate);

        // Second withdrawal after 1 day.
        vm.warp(block.timestamp + 1 days);
        vm.prank(payee);
        scholar.withdraw(payer, payee, rate);

        uint256 remainingEffective = scholar.effectiveBalance(payer);
        console.log("Remaining effective balance after withdrawals:", remainingEffective);
        assertLt(remainingEffective, depositAmount, "Remaining effective balance should be less than deposit");
    }

    /// @notice Test payer withdrawing remaining unstreamed funds.
    function testWithdrawPayer() public {
        uint256 initialBalance = token.balanceOf(payer);
        uint256 depositAmount = 2_000 * 1e6;
        uint256 percentToVault = 0;
        uint256 rate = 5 * 1e6; // 5 tokens/sec

        vm.startPrank(payer);
        scholar.deposit(depositAmount, percentToVault);
        scholar.createStream(payee, rate);
        vm.stopPrank();

        // Warp forward to simulate streaming.
        vm.warp(block.timestamp + 100);
        vm.prank(payee);
        scholar.withdraw(payer, payee, rate); // 2000 - 5 * 100 = 1500 tokens streamed

        uint256 streamed = 100 * rate;
        assertEq(token.balanceOf(payee), streamed, "Payee balance incorrect after withdrawal");

        uint256 remainingEffective = scholar.effectiveBalance(payer);
        console.log("Remaining effective balance before withdrawPayer:", remainingEffective);
        assertEq(remainingEffective, depositAmount - streamed, "Incorrect remaining effective balance");

        console.log("Payer balance before withdrawPayer:", token.balanceOf(payer));
        vm.prank(payer);
        scholar.withdrawPayer(remainingEffective);
        uint256 finalPayerBalance = token.balanceOf(payer);
        console.log("Final payer balance after withdrawPayer:", finalPayerBalance);
        assertEq(finalPayerBalance, initialBalance - streamed, "Payer did not receive correct withdrawal amount");
        assertEq(scholar.effectiveBalance(payer), 0, "Effective balance not zero after withdrawal");
    }

    /// @notice Test the rebalance function: adjust allocation from current ratio to target ratio.
    function testRebalance() public {
        uint256 depositAmount = 1_000 * 1e6;
        uint256 initialPercentToVault = 70;
        vm.prank(payer);
        scholar.deposit(depositAmount, initialPercentToVault);

        uint256 vaultValue = (scholar.vaultShares(payer) * vault.getPricePerShare()) / scholar.SCALE();
        uint256 directValue = scholar.directBalances(payer);
        uint256 totalEffective = directValue + vaultValue;
        uint256 currentVaultRatio = (vaultValue * 100) / totalEffective;
        console.log("Current vault ratio (%):", currentVaultRatio);

        // Target 50:50 ratio
        uint256 targetRatio = 50;
        vm.prank(payer);
        scholar.rebalance(targetRatio);

        vaultValue = (scholar.vaultShares(payer) * vault.getPricePerShare()) / scholar.SCALE();
        directValue = scholar.directBalances(payer);
        totalEffective = directValue + vaultValue;
        uint256 newVaultRatio = (vaultValue * 100) / totalEffective;
        console.log("New vault ratio (%):", newVaultRatio);

        // Allow tolerance of 2%
        assertApproxEqAbs(newVaultRatio, targetRatio, 2, "Rebalance did not achieve target ratio");
    }

    /// @notice Full flow test: deposit, create stream, multiple withdrawals, cancel stream, then final payer withdrawal.
    function testFullFlow() public {
        uint256 depositAmount = 5_000 * 1e6;
        uint256 percentToVault = 70;
        uint256 rate = 10 * 1e6; // 10 tokens/sec

        vm.prank(payer);
        scholar.deposit(depositAmount, percentToVault);
        console.log("Effective balance after deposit:", scholar.effectiveBalance(payer));

        vm.prank(payer);
        scholar.createStream(payee, rate);
        console.log("Stream created.");

        // After 50 seconds, payee withdraws streaming funds.
        vm.warp(block.timestamp + 50);
        vm.prank(payee);
        scholar.withdraw(payer, payee, rate);
        uint256 firstWithdrawal = 50 * rate;
        console.log("Payee balance after first withdrawal:", token.balanceOf(payee));

        // After additional 100 seconds, payee withdraws again.
        vm.warp(block.timestamp + 100);
        vm.prank(payee);
        scholar.withdraw(payer, payee, rate);
        uint256 secondWithdrawal = 100 * rate;
        uint256 totalPayeeBalance = token.balanceOf(payee);
        console.log("Payee balance after second withdrawal:", totalPayeeBalance);

        // Cancel the stream.
        vm.prank(payer);
        scholar.cancelStream(payee, rate);
        console.log("Stream cancelled.");
        uint256 remainingEffective = scholar.effectiveBalance(payer);
        console.log("Remaining effective balance after cancellation:", remainingEffective);

        // Final withdrawal by payer.
        vm.prank(payer);
        scholar.withdrawPayer(remainingEffective);
        uint256 finalPayerBalance = token.balanceOf(payer);
        console.log("Final payer token balance after withdrawal:", finalPayerBalance);
        assertEq(scholar.effectiveBalance(payer), 0, "Effective balance should be zero after full withdrawal");
    }

    /// @notice Test yield accrual: simulate yield in vault and verify effective balance increases.
    function testYieldAccrual() public {
        uint256 depositAmount = 1_000 * 1e6;
        uint256 percentToVault = 80; // Deposit most funds in vault

        vm.prank(payer);
        scholar.deposit(depositAmount, percentToVault);

        uint256 effectiveBefore = scholar.effectiveBalance(payer);
        console.log("Effective balance before yield:", effectiveBefore);

        // Simulate yield: add extra 100 tokens to vault underlying.
        uint256 yieldAmount = 100 * 1e6;
        vault.simulateYield(yieldAmount);

        uint256 effectiveAfter = scholar.effectiveBalance(payer);
        console.log("Effective balance after yield:", effectiveAfter);

        assertGt(effectiveAfter, effectiveBefore, "Effective balance did not increase after yield");
    }
}

