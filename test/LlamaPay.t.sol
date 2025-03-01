// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LlamaPay} from "../src/LlamaPay.sol";
import {LlamaPayFactory} from "../src/LlamaPayFactory.sol";
import {MockToken} from "../src/mock/MockToken.sol";

contract PayStreamTest is Test {

    uint256 MONTH = 24 * 3600 * 30;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum"));
    }

    function helper_basicSetup() internal returns (LlamaPay, address, address, address, address, uint256) {
        (, MockToken mockToken, LlamaPay llamaPay) = helper_deployAll(18); 

        address payer = vm.addr(1);
        address payee = vm.addr(2);
        address payee2 = vm.addr(3);

        mockToken.transfer(payer, 2 ** 255 - 1);

        vm.startPrank(payer);

        mockToken.approve(address(llamaPay), 999999999999999999999999999999999);

        uint256 DECIMALS_DIVISOR = llamaPay.DECIMALS_DIVISOR();

        vm.stopPrank();

        return (llamaPay, payer, payee, payee2, address(mockToken), DECIMALS_DIVISOR);
    }

    function helper_deployAll(uint8 _tokenDecimals) internal returns (LlamaPayFactory, MockToken, LlamaPay) {
        MockToken mockToken = new MockToken(_tokenDecimals);

        LlamaPayFactory factory = new LlamaPayFactory();
        factory.createLlamaPayContract(address(mockToken));

        address llamaPayAddress = factory.getLlamaPayContractByIndex(0);
        LlamaPay llamaPay = LlamaPay(llamaPayAddress);

        return (factory, mockToken, llamaPay);
    }

    function helper_setupStream(uint256 _monthlyTotal, uint8 _tokenDecimals) internal returns (LlamaPay, address, address, address, address, uint216) {
        (, MockToken mockToken, LlamaPay llamaPay) = helper_deployAll(_tokenDecimals);

        address payer = vm.addr(1);
        address payee = vm.addr(2);
        address payee2 = vm.addr(3);

        mockToken.transfer(payer, 2 ** 255 - 1);

        vm.startPrank(payer);

        mockToken.approve(address(llamaPay), 999999999999999999999999999999999);

        uint256 DECIMALS_DIVISOR = llamaPay.DECIMALS_DIVISOR();

        uint256 monthlySalary = 10 ** _tokenDecimals * _monthlyTotal;
        uint216 perSec = uint216(monthlySalary * DECIMALS_DIVISOR / MONTH);

        llamaPay.createStream(payee, uint216(perSec));
        llamaPay.deposit(monthlySalary * 2);

        vm.stopPrank();

        vm.warp(block.timestamp + MONTH - 1);

        return (llamaPay, payer, payee, payee2, address(mockToken), perSec);
    }

    function helper_setupStreamAndWithdraw(uint256 _monthlyTotal, uint8 _tokenDecimals) internal returns (uint256 totalPaid) {
        (LlamaPay llamaPay, address payer, address payee, , address token, uint256 perSec) = helper_setupStream(_monthlyTotal, _tokenDecimals);

        vm.startPrank(payer);
        llamaPay.withdraw(payer, payee, uint216(perSec));
        vm.stopPrank();

        totalPaid = MockToken(token).balanceOf(payee);
    }

    // can't withdraw on a cancelled stream
    function test_CantWithdrawOnCancelledStream() public {
        (LlamaPay llamaPay, address payer, address payee, , , uint216  perSec) = helper_setupStream(1e6, 18);

        vm.startPrank(payer);

        llamaPay.cancelStream(payee, perSec);
        vm.expectRevert("stream doesn't exist");
        llamaPay.withdraw(payer, payee, perSec);
        
        vm.stopPrank();
    }

    // withdrawPayer works and if withdraw is called after less than perSec funds are left in contract
    function test_WithdrawPayer() public {
        (LlamaPay llamaPay, address payer, address payee, , address token, uint216 perSec) = helper_setupStream(10e3, 18);

        vm.startPrank(payer);
    
        // Withdraw 5,000 * 1e3
        llamaPay.withdrawPayer(5e3 * 1e3);

        // Check remaining balance
        int256 left = llamaPay.getPayerBalance(payer);
        assertGt(left, 9_999 * 1e18);

        // Withdraw all remaining funds
        llamaPay.withdrawPayerAll();
    
        // Check if balance is 0 (or slightly negative due to elapsed time)
        int256 left2 = llamaPay.getPayerBalance(payer);
        assertEq(left2, 0);

        // Withdraw stream
        llamaPay.withdraw(payer, payee, perSec);
    
        // Check if contract token balance is now less than `perSec`
        assertLt(MockToken(token).balanceOf(address(llamaPay)), perSec);

        vm.stopPrank();
    }

    function test_ModifyStream() public {
        (LlamaPay llamaPay, address payer, address payee, address payee2, , uint216 perSec) = helper_setupStream(1e6, 18);

        vm.startPrank(payer);

        bytes32 streamId = llamaPay.getStreamId(payer, payee, perSec);
        uint256 statusBefore = llamaPay.streamToStart(streamId);
        assertNotEq(statusBefore, 0);

        llamaPay.modifyStream(payee, perSec, payee2, 20);
        uint256 statusAfter = llamaPay.streamToStart(streamId);
        assertEq(statusAfter, 0);

        vm.stopPrank();
    }

    function sameNum(uint256 n1, uint256 n2, uint8 precision) internal pure {
        uint256 factor = 10 ** precision;
        assertEq(n1 / (1e18 / factor), n2 * factor);
    }

    function assertBalanceOf(address token, address account, uint256 amount) internal view {
        sameNum(MockToken(token).balanceOf(account), amount, 2);
    }

    // standard flow with multiple payees and payers
    function test_StandardFlow() public {
        (
            LlamaPay llamaPay,
            address payer,
            address payee,
            address payee2,
            address token,
            uint256 DECIMALS_DIVISOR
        ) = helper_basicSetup();

        uint256 total = 10_000 ether;

        vm.startPrank(payer);

        MockToken(token).transfer(address(llamaPay), total * 10); 

        uint256 monthly1k = total * DECIMALS_DIVISOR / 10 / MONTH;
        llamaPay.depositAndCreate(total, payee, uint216(monthly1k * 5));

        vm.warp(block.timestamp + MONTH / 2);

        llamaPay.createStream(payee2, uint216(monthly1k * 10));

        vm.stopPrank();

        vm.prank(payee2);
        llamaPay.withdraw(payer, payee, uint216(monthly1k * 5));

        console.log('balance of payee', MockToken(token).balanceOf(payee));

        vm.warp(block.timestamp + MONTH);

        vm.startPrank(payer);

        llamaPay.withdraw(payer, payee, uint216(monthly1k * 5));
        console.log('balance of payee', MockToken(token).balanceOf(payee));

        llamaPay.withdraw(payer, payee2, uint216(monthly1k * 10));
        console.log('balance of payee2', MockToken(token).balanceOf(payee2));

        vm.stopPrank();
    }
}
