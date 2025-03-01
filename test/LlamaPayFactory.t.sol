// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LlamaPay} from "../src/LlamaPay.sol";
import {LlamaPayFactory} from "../src/LlamaPayFactory.sol";

contract FactoryTest is Test {
    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum"));
    }
}
