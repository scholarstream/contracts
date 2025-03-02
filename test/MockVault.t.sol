// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./mocks/MockVault.sol";
import "./mocks/MockToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC4626Test is Test {
    MockToken token;
    MockVault vault;
    address user = address(0x123);

    function setUp() public {
        // Deploy a test token with 18 decimals and the ERC4626 vault using that token.
        token = new MockToken("Test Token", 18);
        vault = new MockVault(IERC20(address(token)));
        // Mint tokens to user (for example, 1000 tokens)
        token.mint(user, 1e21); // 1e21 = 1,000 tokens (18 decimals)
        vm.startPrank(user);
        // Approve the vault to spend tokens on user's behalf (or unlimited for simplicity)
        token.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function testDeposit() public {
        vm.startPrank(user);
        uint256 depositAmount = 1e18; // deposit 1 token
        uint256 shares = vault.deposit(depositAmount, user);
        // In a simple vault with pricePerShare == 1, shares minted equals depositAmount.
        assertEq(shares, depositAmount);
        assertEq(vault.totalAssets(), depositAmount);
        assertEq(vault.totalSupply(), depositAmount);
        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(user);
        uint256 depositAmount = 2e18; // deposit 2 tokens
        vault.deposit(depositAmount, user);
        // Withdraw half of the deposit
        uint256 withdrawAmount = 1e18;
        // Redeem tokens: redeem() returns the number of shares burned.
        uint256 sharesRedeemed = vault.redeem(withdrawAmount, user, user);
        // In a vault with a 1:1 ratio, shares redeemed equals the withdraw amount.
        assertEq(sharesRedeemed, withdrawAmount);
        // Verify that user's token balance increased by the withdrawn amount.
        // User originally had 1e21 tokens, then deposited 2e18, so balance became (1e21 - 2e18).
        // After withdrawing 1e18, balance should be (1e21 - 2e18 + 1e18) = 1e21 - 1e18.
        uint256 expectedBalance = 1e21 - 1e18;
        assertEq(token.balanceOf(user), expectedBalance);
        vm.stopPrank();
    }

    function testConvertFunctions() public {
        vm.startPrank(user);
        uint256 depositAmount = 1e18;
        uint256 sharesFromDeposit = vault.deposit(depositAmount, user);
        // With pricePerShare == 1, convertToShares should return the same value as depositAmount.
        uint256 previewShares = vault.convertToShares(depositAmount);
        // And convertToAssets should return the original deposit amount for those shares.
        uint256 previewAssets = vault.convertToAssets(sharesFromDeposit);
        assertEq(sharesFromDeposit, previewShares);
        assertEq(previewAssets, depositAmount);
        vm.stopPrank();
    }
}

