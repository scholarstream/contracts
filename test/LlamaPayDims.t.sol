// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Adapter} from "../src/Adapter.sol";
import {LlamaPay} from "../src/LlamaPay.sol";
import {LlamaPayFactory} from "../src/LlamaPayFactory.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {MockVault} from "./mocks/MockVault.sol";

/// @title PayerTest
/// @notice Tests the complete flow of depositing, creating a stream, and withdrawing funds.
contract PayerTest is Test {
    function testCreateStreamFlow() public {
        // Deploy factory, token, and LlamaPay contract.
        LlamaPayFactory factory = new LlamaPayFactory();
        MockToken token = new MockToken("USDC", 6);
        LlamaPay payContract = factory.createPayContract(address(token));

        // Set up payer and payee addresses.
        address payer = vm.addr(1);
        address payee = vm.addr(2);

        // Mint tokens to payer.
        token.mint(payer, 10_000 * 1e6);

        // Start acting as payer.
        vm.startPrank(payer);
        token.approve(address(payContract), 10_000 * 1e6);

        // Log balances before deposit.
        console.log("==============================");
        console.log("Before Deposit");
        console.log("Payer balance", token.balanceOf(payer));
        console.log("PayContract balance", token.balanceOf(address(payContract)));
        console.log("Payee balance", token.balanceOf(payee));

        // Deposit tokens into the contract.
        payContract.deposit(10_000 * 1e6);

        // Log balances after deposit.
        console.log("==============================");
        console.log("After Deposit");
        console.log("Payer balance", token.balanceOf(payer));
        console.log("PayContract balance", token.balanceOf(address(payContract)));
        console.log("Payee balance", token.balanceOf(payee));

        // Create a streaming payment from payer to payee.
        uint256 amountPerSec = 2;
        payContract.createStream(payee, amountPerSec);

        // Log initial stream state.
        {
            bytes32 streamId = payContract.getStreamId(payer, payee, amountPerSec);
            uint256 elapsed = block.timestamp - payContract.streamToStart(streamId);
            uint256 totalPaid = elapsed * amountPerSec;
            console.log("Total paid at stream creation (t = 0):", totalPaid);
        }

        // Warp forward by 10 seconds and log streamed amount.
        vm.warp(block.timestamp + 10);
        {
            bytes32 streamId = payContract.getStreamId(payer, payee, amountPerSec);
            uint256 elapsed = block.timestamp - payContract.streamToStart(streamId);
            uint256 totalPaid = elapsed * amountPerSec;
            console.log("Total paid after 10 seconds:", totalPaid);
        }
        vm.stopPrank();

        // Payee withdraws streamed funds.
        vm.startPrank(payee);
        console.log("==============================");
        console.log("Before Withdraw");
        console.log("Payer balance", token.balanceOf(payer));
        console.log("PayContract balance", token.balanceOf(address(payContract)));
        console.log("Payee balance", token.balanceOf(payee));

        // First withdrawal.
        payContract.withdraw(payer, payee, amountPerSec);
        console.log("==============================");
        console.log("After First Withdraw");
        console.log("Payer balance", token.balanceOf(payer));
        console.log("PayContract balance", token.balanceOf(address(payContract)));
        console.log("Payee balance", token.balanceOf(payee));
        console.log("Remaining principal for payer:", payContract.balances(payer));

        // Warp forward by 1 day for additional streaming.
        vm.warp(block.timestamp + 1 days);
        payContract.withdraw(payer, payee, amountPerSec);
        console.log("==============================");
        console.log("After Second Withdraw");
        console.log("Payer balance", token.balanceOf(payer));
        console.log("PayContract balance", token.balanceOf(address(payContract)));
        console.log("Payee balance", token.balanceOf(payee));
        console.log("Remaining principal for payer:", payContract.balances(payer));
        vm.stopPrank();

        // Payer withdraws any remaining unstreamed funds.
        vm.startPrank(payer);
        uint256 remainingPrincipal = payContract.balances(payer);
        payContract.withdrawPayer(remainingPrincipal);
        console.log("==============================");
        console.log("After Payer Withdraw of remaining funds");
        console.log("Payer balance", token.balanceOf(payer));
        console.log("PayContract balance", token.balanceOf(address(payContract)));
        console.log("Payee balance", token.balanceOf(payee));
        vm.stopPrank();
    }
}

