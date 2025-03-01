// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Adapter} from "../src/Adapter.sol";
import {LlamaPay} from "../src/LlamaPay.sol";
import {LlamaPayFactory} from "../src/LlamaPayFactory.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {MockVault} from "./mocks/MockVault.sol";

contract MockAdapter is Adapter {
    function deposit(address vault, uint256 amount) public override {
        MockVault(vault).deposit(amount, msg.sender);
    }

    function withdraw(address vault, uint256 amount) public override {
        MockVault(vault).withdraw(amount, msg.sender, msg.sender);
    }

    function pricePerShare(address vault) public view override returns (uint256) {
        return MockVault(vault).previewRedeem(1 ether);
    }
}

contract PayerTest is Test {
    function test_PayerCreateStream() public {
        LlamaPayFactory factory = new LlamaPayFactory();
        MockToken token = new MockToken("USDC", 6);
        MockVault vault = new MockVault(token);
        MockAdapter adapter = new MockAdapter();
        LlamaPay payContract = factory.createPayContract(
            address(token), 
            address(adapter), 
            address(vault)
        );

        address payer = vm.addr(1);
        address payee = vm.addr(2);
        token.mint(payer, 10_000 * 1e6);

        vm.startPrank(payer);
        token.approve(address(payContract), 10_000 * 1e6);
        payContract.deposit(10_000 * 1e6);

        console.log("After Deposit");
        console.log("Payer balance", token.balanceOf(payer));
        console.log("Vault balance", token.balanceOf(address(vault)));
        console.log("Vault pricePerShare", adapter.pricePerShare(address(vault)));
        console.log("block.timestamp", block.timestamp);

        uint256 amountPerSec = 2;
        payContract.createStream(payee, amountPerSec);

        {
            bytes32 streamId = payContract.getStreamId(payer, payee, amountPerSec);
            uint256 delta = block.timestamp - payContract.streamToStart(streamId);
            uint256 totalPaid = delta * amountPerSec;

            console.log("totalPaid at t = 0", totalPaid);
        }

        vm.warp(block.timestamp + 10);

        {
            bytes32 streamId = payContract.getStreamId(payer, payee, amountPerSec);
            uint256 delta = block.timestamp - payContract.streamToStart(streamId);
            uint256 totalPaid = delta * amountPerSec;

            console.log("totalPaid t = 10s", totalPaid);
        }

        // payContract.withdrawPayer(10_000 * 1e6);

        // console.log("After Withdraw Payer");
        // console.log("Payer balance", token.balanceOf(payer));
        // console.log("Vault balance", token.balanceOf(address(vault)));
    }
}
