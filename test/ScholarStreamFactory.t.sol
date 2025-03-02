// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ScholarStream} from "../src/ScholarStream.sol";
import {ScholarStreamFactory} from "../src/ScholarStreamFactory.sol";

contract FactoryTest is Test {
    function test_createPayContract() public {
        ScholarStreamFactory factory = new ScholarStreamFactory();
        address token = vm.addr(1);
        ScholarStream payContract = factory.createPayContract(token);

        // assert that the payContract was created
        assertEq(address(payContract), address(factory.getPayContract(token)));

        // assert that the payContract was added to the array
        assertEq(address(payContract), address(factory.payContractsArray(0)));

        // assert that the payContractsArrayLength was incremented
        assertEq(factory.payContractsArrayLength(), 1);

        // assert that payContract has correct token, adapter, and vault
        assertEq(address(payContract.token()), token);
        // assertEq(address(payContract.adapter()), adapter);
        // assertEq(address(payContract.vault()), vault);
    }
}
