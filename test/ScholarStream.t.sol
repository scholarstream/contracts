// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ScholarStream} from "../src/ScholarStream.sol";
import {ScholarStreamFactory} from "../src/ScholarStreamFactory.sol";
import {MockToken} from "./mocks/MockToken.sol";

contract StreamTest is Test {
  ScholarStreamFactory factory;
  MockToken token;
  ScholarStream payContract;
  address payer;
  address payee;

  /// @notice Deploy the contracts and prepare test addresses.
  function setUp() public {
    factory = new ScholarStreamFactory();
    token = new MockToken("USDC", 6);
    payContract = factory.createPayContract(address(token));
    payer = vm.addr(1);
    payee = vm.addr(2);
    token.mint(payer, 10_000 * 1e6);
  }

  /// @notice Executes the full flow: deposit, create a stream, simulate time passage with withdrawals,
  /// cancel the stream, then withdraw remaining funds.
  function testFullFlow() public {
    uint256 depositAmount = 10_000 * 1e6;
    uint256 amountPerSec = 2;

    // --- Step 1: Deposit ---
    vm.startPrank(payer);
    token.approve(address(payContract), depositAmount);
    console.log("=== Step 1: Deposit ===");
    console.log("Before Deposit:");
    console.log("  Payer token balance:", token.balanceOf(payer));
    console.log(
      "  Contract token balance:",
      token.balanceOf(address(payContract))
    );
    payContract.deposit(depositAmount);
    console.log("After Deposit:");
    console.log("  Payer token balance:", token.balanceOf(payer));
    console.log(
      "  Contract token balance:",
      token.balanceOf(address(payContract))
    );

    // --- Step 2: Create Stream ---
    payContract.createStream(payee, amountPerSec);

    bytes32 streamId = payContract.getStreamId(payer, payee, amountPerSec);
    uint256 startTime = payContract.streamToStart(streamId);
    console.log("=== Step 2: Stream Creation ===");
    console.log("Stream Created:");
    console.log("  Stream ID:", uint256(streamId));
    console.log("  Stream Start Time:", startTime);

    vm.stopPrank();

    // --- Step 3: First Withdrawal after 10 seconds ---
    vm.warp(block.timestamp + 10);

    vm.startPrank(payee);
    payContract.withdraw(payer, payee, amountPerSec);

    uint256 firstWithdrawalAmount = 10 * amountPerSec;
    console.log("=== Step 3: First Withdrawal (after 10 seconds) ===");
    console.log("  Expected first withdrawal amount:", firstWithdrawalAmount);
    console.log("  Payee token balance:", token.balanceOf(payee));

    // --- Step 4: Second Withdrawal after 1 day ---
    vm.warp(block.timestamp + 1 days);

    payContract.withdraw(payer, payee, amountPerSec);

    uint256 secondWithdrawalAmount = 86400 * amountPerSec;
    console.log("=== Step 4: Second Withdrawal (after 1 day) ===");
    console.log("  Expected second withdrawal amount:", secondWithdrawalAmount);
    console.log(
      "  Total expected payee balance:",
      firstWithdrawalAmount + secondWithdrawalAmount
    );
    console.log("  Payee token balance:", token.balanceOf(payee));
    console.log("  Payer remaining principal:", payContract.balances(payer));

    vm.stopPrank();

    // --- Step 5: Cancel the Stream ---

    vm.startPrank(payer);
    payContract.cancelStream(payee, amountPerSec);

    console.log("=== Step 5: Cancel Stream ===");
    console.log("Stream cancelled.");
    console.log(
      "  Payer's total streaming rate:",
      payContract.totalPaidPerSec(payer)
    );
    console.log(
      "  Payer remaining principal after cancelling stream:",
      payContract.balances(payer)
    );
    console.log(
      "  Contract token balance:",
      token.balanceOf(address(payContract))
    );

    // --- Step 6: Payer Withdraws Remaining Funds ---
    uint256 remainingPrincipal = payContract.balances(payer);

    payContract.withdrawPayer(remainingPrincipal);

    console.log(
      "=== Step 6: Payer Withdraws Remaining Funds (after withdraw payer) ==="
    );
    console.log("  Payer token balance:", token.balanceOf(payer));
    console.log(
      "  Contract token balance:",
      token.balanceOf(address(payContract))
    );
    console.log("  Payer remaining principal:", payContract.balances(payer));

    vm.stopPrank();
  }

  /// @notice Tests the deposit functionality by verifying token balances.
  function testDeposit() public {
    vm.startPrank(payer);
    token.approve(address(payContract), 10_000 * 1e6);

    uint256 initialPayerBalance = token.balanceOf(payer);
    uint256 initialContractBalance = token.balanceOf(address(payContract));

    payContract.deposit(10_000 * 1e6);

    uint256 afterDepositPayerBalance = token.balanceOf(payer);
    uint256 afterDepositContractBalance = token.balanceOf(address(payContract));

    // Verify that exactly 10,000 USDC (with 6 decimals) were transferred.
    assertEq(initialPayerBalance - afterDepositPayerBalance, 10_000 * 1e6);
    assertEq(
      afterDepositContractBalance - initialContractBalance,
      10_000 * 1e6
    );
    vm.stopPrank();
  }

  /// @notice Tests creating a stream and verifies that the stream start time is recorded.
  function testStreamCreation() public {
    vm.startPrank(payer);
    token.approve(address(payContract), 10_000 * 1e6);
    payContract.deposit(10_000 * 1e6);

    uint256 amountPerSec = 2;
    payContract.createStream(payee, amountPerSec);

    bytes32 streamId = payContract.getStreamId(payer, payee, amountPerSec);
    uint256 streamStart = payContract.streamToStart(streamId);
    // The stream start time should be set (non-zero).
    assertGt(streamStart, 0);
    vm.stopPrank();
  }

  /// @notice Tests the first withdrawal from the stream after a short time lapse.
  function testWithdrawStreamFirst() public {
    // Set up: deposit funds and create a stream.
    vm.startPrank(payer);
    token.approve(address(payContract), 10_000 * 1e6);
    payContract.deposit(10_000 * 1e6);
    uint256 amountPerSec = 2;
    payContract.createStream(payee, amountPerSec);
    vm.stopPrank();

    // Get the initial stream start time.
    bytes32 streamId = payContract.getStreamId(payer, payee, amountPerSec);

    // Warp forward 10 seconds.
    vm.warp(block.timestamp + 10);

    // Payee withdraws the streamed funds.
    vm.startPrank(payee);
    payContract.withdraw(payer, payee, amountPerSec);
    vm.stopPrank();

    // Verify that the stream start time was updated to the last update timestamp.
    uint256 updatedStart = payContract.streamToStart(streamId);
    assertEq(updatedStart, payContract.lastPayerUpdate(payer));
  }

  /// @notice Tests withdrawing from the stream in two steps with a time gap.
  function testWithdrawStreamAfterOneDay() public {
    // Set up: deposit funds and create a stream.
    vm.startPrank(payer);
    token.approve(address(payContract), 10_000 * 1e6);
    payContract.deposit(10_000 * 1e6);
    uint256 amountPerSec = 2;
    payContract.createStream(payee, amountPerSec);
    vm.stopPrank();

    // First withdrawal after 10 seconds.
    vm.warp(block.timestamp + 10);
    vm.startPrank(payee);
    payContract.withdraw(payer, payee, amountPerSec);
    vm.stopPrank();

    // Second withdrawal after an additional day.
    vm.warp(block.timestamp + 1 days);
    vm.startPrank(payee);
    payContract.withdraw(payer, payee, amountPerSec);
    vm.stopPrank();

    // Ensure that the payer's remaining principal is less than the initial deposit.
    uint256 remainingPrincipal = payContract.balances(payer);
    assertLt(remainingPrincipal, 10_000 * 1e6);
  }

  /// @notice Tests the payer withdrawing remaining unstreamed funds.
  function testWithdrawPayer() public {
    // Set up: deposit funds and create a stream.
    vm.startPrank(payer);
    token.approve(address(payContract), 10_000 * 1e6);
    payContract.deposit(10_000 * 1e6);
    uint256 amountPerSec = 2;
    payContract.createStream(payee, amountPerSec);
    vm.stopPrank();

    // Advance time to simulate streaming.
    vm.warp(block.timestamp + 100);

    // Have payee withdraw the streamed funds.
    vm.startPrank(payee);
    payContract.withdraw(payer, payee, amountPerSec);
    vm.stopPrank();

    // Payer withdraws the remaining unstreamed funds.
    vm.startPrank(payer);
    uint256 remainingPrincipal = payContract.balances(payer);
    payContract.withdrawPayer(remainingPrincipal);

    // Verify that the payer's principal balance is now zero.
    assertEq(payContract.balances(payer), 0);
    vm.stopPrank();
  }
}
