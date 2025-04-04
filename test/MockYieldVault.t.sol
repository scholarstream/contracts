// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockYieldVault} from "../src/mocks/MockYieldVault.sol";

contract MockYieldVaultTest is Test {
  MockToken token;
  MockYieldVault public vault;

  function setUp() public {
    token = new MockToken("USDC Mock", "USDC", 6);
    vault = new MockYieldVault(address(token));
  }
}
