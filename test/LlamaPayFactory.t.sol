// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LlamaPay} from "../src/LlamaPay.sol";
import {LlamaPayFactory} from "../src/LlamaPayFactory.sol";

contract FactoryTest is Test {
    function test_createPayContract() public {
        LlamaPayFactory factory = new LlamaPayFactory();
        address token = vm.addr(1);
        address adapter = vm.addr(2);
        address vault = vm.addr(3);
        LlamaPay payContract = factory.createPayContract(token, adapter, vault);

        // assert that the payContract was created
        assertEq(address(payContract), address(factory.getPayContract(token, adapter, vault)));

        // assert that the payContract was added to the array
        assertEq(address(payContract), address(factory.payContractsArray(0)));

        // assert that the payContractsArrayLength was incremented
        assertEq(factory.payContractsArrayLength(), 1);
    }
}
