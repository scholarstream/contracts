// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ScholarStreamYield} from "../src/ScholarStreamYield.sol";
import {ScholarStreamYieldFactory} from "../src/ScholarStreamYieldFactory.sol";

contract FactoryTest is Test {
  function test_createPayContract() public {
    ScholarStreamYieldFactory factory = new ScholarStreamYieldFactory();
    address token = vm.addr(1);
    address vault = vm.addr(2);
    ScholarStreamYield payContract = factory.createPayContract(token, vault);

    // assert that the payContract was created
    assertEq(
      address(payContract),
      address(factory.getPayContract(token, vault))
    );

    // assert that the payContract was added to the array
    assertEq(address(payContract), address(factory.payContractsArray(0)));

    // assert that the payContractsArrayLength was incremented
    assertEq(factory.payContractsArrayLength(), 1);

    // assert that payContract has correct token, adapter, and vault
    assertEq(address(payContract.token()), token);
    assertEq(address(payContract.vault()), vault);
  }
}
