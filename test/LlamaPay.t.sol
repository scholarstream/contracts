// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
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
    LlamaPayFactory factory;
    MockToken token;
    MockVault vault;
    MockAdapter adapter;
    LlamaPay payContract;
    address payer;
    address payee;

    function setUp() public {
        factory = new LlamaPayFactory();
        token = new MockToken("USDC", 6);
        vault = new MockVault(token);
        adapter = new MockAdapter();
        payContract = factory.createPayContract(
            address(token), 
            address(adapter), 
            address(vault)
        );
        payer = vm.addr(1);
        payee = vm.addr(2);
        token.mint(payer, 10_000 * 1e6);
    }

    function testDeposit() public {
        vm.startPrank(payer);
        token.approve(address(payContract), 10_000 * 1e6);
        uint256 initialPayerBalance = token.balanceOf(payer);
        payContract.deposit(10_000 * 1e6);
        assertEq(token.balanceOf(payer), initialPayerBalance - 10_000 * 1e6);
        assertEq(payContract.balances(payer), 10_000 * 1e6);
        vm.stopPrank();
    }

    function testCreateStream() public {
        vm.startPrank(payer);
        token.approve(address(payContract), 10_000 * 1e6);
        payContract.deposit(10_000 * 1e6);
        uint256 amountPerSec = 2;
        payContract.createStream(payee, amountPerSec);
        bytes32 streamId = payContract.getStreamId(payer, payee, amountPerSec);
        uint256 streamStart = payContract.streamToStart(streamId);
        assertGt(streamStart, 0);
        assertEq(payContract.totalPaidPerSec(payer), amountPerSec);
        vm.stopPrank();
    }

    function testWithdrawStream() public {
        vm.startPrank(payer);
        token.approve(address(payContract), 10_000 * 1e6);
        payContract.deposit(10_000 * 1e6);
        uint256 amountPerSec = 2;
        payContract.createStream(payee, amountPerSec);
        bytes32 streamId = payContract.getStreamId(payer, payee, amountPerSec);
        uint256 start = payContract.streamToStart(streamId);

        vm.warp(block.timestamp + 10);
        uint256 payeeBalanceBefore = token.balanceOf(payee);
        payContract.withdraw(payer, payee, amountPerSec);
        // stream start is updated to current block.timestamp
        assertEq(payContract.streamToStart(streamId), block.timestamp);
        uint256 payeeBalanceAfter = token.balanceOf(payee);
        assertGt(payeeBalanceAfter, payeeBalanceBefore);
        vm.stopPrank();
    }

    function testCancelStream() public {
        vm.startPrank(payer);
        token.approve(address(payContract), 10_000 * 1e6);
        payContract.deposit(10_000 * 1e6);
        uint256 amountPerSec = 2;
        payContract.createStream(payee, amountPerSec);
        bytes32 streamId = payContract.getStreamId(payer, payee, amountPerSec);
        payContract.cancelStream(payee, amountPerSec);
        assertEq(payContract.streamToStart(streamId), 0);
        assertEq(payContract.totalPaidPerSec(payer), 0);
        vm.stopPrank();
    }

    function testModifyStream() public {
        vm.startPrank(payer);
        token.approve(address(payContract), 10_000 * 1e6);
        payContract.deposit(10_000 * 1e6);
        uint256 oldAmountPerSec = 2;
        uint256 newAmountPerSec = 3;
        payContract.createStream(payee, oldAmountPerSec);
        bytes32 oldStreamId = payContract.getStreamId(payer, payee, oldAmountPerSec);
        assertGt(payContract.streamToStart(oldStreamId), 0);
        payContract.modify(payee, oldAmountPerSec, payee, newAmountPerSec);
        bytes32 newStreamId = payContract.getStreamId(payer, payee, newAmountPerSec);
        assertEq(payContract.streamToStart(oldStreamId), 0);
        assertGt(payContract.streamToStart(newStreamId), 0);
        assertEq(payContract.totalPaidPerSec(payer), newAmountPerSec);
        vm.stopPrank();
    }

    function testWithdrawPayer() public {
        vm.startPrank(payer);
        token.approve(address(payContract), 10_000 * 1e6);
        payContract.deposit(10_000 * 1e6);
        uint256 amountPerSec = 2;
        payContract.createStream(payee, amountPerSec);
        vm.warp(block.timestamp + 20);
        uint256 contractBalanceBefore = token.balanceOf(address(payContract));
        payContract.withdrawPayer(1000 * 1e6);
        uint256 contractBalanceAfter = token.balanceOf(address(payContract));
        assertLt(contractBalanceAfter, contractBalanceBefore);
        assertEq(token.balanceOf(payer), 1000 * 1e6);
        vm.stopPrank();
    }

    function testCannotCreateDuplicateStream() public {
        vm.startPrank(payer);
        token.approve(address(payContract), 10_000 * 1e6);
        payContract.deposit(10_000 * 1e6);
        uint256 amountPerSec = 2;
        payContract.createStream(payee, amountPerSec);
        vm.expectRevert("stream already exists");
        payContract.createStream(payee, amountPerSec);
        vm.stopPrank();
    }

    function testDepositWithoutApproval() public {
        vm.startPrank(payer);
        vm.expectRevert();
        payContract.deposit(10_000 * 1e6);
        vm.stopPrank();
    }
}

