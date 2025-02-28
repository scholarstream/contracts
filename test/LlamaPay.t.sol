// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LlamaPay} from "../src/LlamaPay.sol";
import {LlamaPayFactory} from "../src/LlamaPayFactory.sol";
import {MockToken} from "../src/mock/MockToken.sol";

contract PayStreamTest is Test {
    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum"));
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

        address payer = address(this);
        address payee = vm.addr(1);
        address payee2 = vm.addr(2);

        mockToken.approve(address(llamaPay), 999999999999999999999999999999999);

        uint256 MONTH = 24 * 3600 * 30;
        uint256 DECIMALS_DIVISOR = llamaPay.DECIMALS_DIVISOR();

        uint256 monthlySalary = 10 ** _tokenDecimals * _monthlyTotal;
        uint216 perSec = uint216(monthlySalary * DECIMALS_DIVISOR / MONTH);

        llamaPay.createStream(payee, uint216(perSec));
        llamaPay.deposit(monthlySalary * 2);

        vm.warp(block.timestamp + MONTH - 1);

        return (llamaPay, payer, payee, payee2, address(mockToken), perSec);
    }

    function helper_setupStreamAndWithdraw(uint256 _monthlyTotal, uint8 _tokenDecimals) internal returns (uint256 totalPaid) {
        (LlamaPay llamaPay, address payer, address payee, , address token, uint256 perSec) = helper_setupStream(_monthlyTotal, _tokenDecimals);

        llamaPay.withdraw(payer, payee, uint216(perSec));
        totalPaid = MockToken(token).balanceOf(payee);
    }

    // can't withdraw on a cancelled stream
    function test_CantWithdrawOnCancelledStream() public {
        (LlamaPay llamaPay, address payer, address payee, , , uint216  perSec) = helper_setupStream(1e6, 18);

        llamaPay.cancelStream(payee, perSec);
        vm.expectRevert("stream doesn't exist");
        llamaPay.withdraw(payer, payee, perSec);
    }
}
