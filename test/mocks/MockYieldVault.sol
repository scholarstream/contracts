// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IYieldVault} from "../../src/ScholarStreamYield.sol";

/// @title MockYieldVault
/// @notice A mock yield vault that simulates yield accrual by increasing total underlying tokens.
/// Deposits mint shares based on the vault’s current state, and withdrawals redeem shares for underlying tokens.
contract MockYieldVault is IYieldVault {
    IERC20 public token;
    uint256 public totalUnderlying;
    uint256 public totalShares;
    uint256 public constant SCALE = 1e18;

    /// @notice Deploys the vault for the specified token.
    constructor(address _token) {
        token = IERC20(_token);
    }

    /// @notice Deposits `amount` tokens into the vault and returns the number of shares minted.
    /// @dev If there are no shares yet, 1 share is minted per token.
    function deposit(uint256 amount, address receiver) external override returns (uint256 shares) {
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        if (totalShares == 0 || totalUnderlying == 0) {
            shares = amount;
        } else {
            shares = (amount * totalShares) / totalUnderlying;
        }
        totalUnderlying += amount;
        totalShares += shares;
        // For simplicity, we're not tracking per-address share balances here.
        return shares;
    }

    /// @notice Withdraws tokens by redeeming `shares` from the vault.
    /// @return amount The amount of tokens redeemed.
    function withdraw(uint256 shares, address receiver) external override returns (uint256 amount) {
        require(shares <= totalShares, "Not enough shares");
        // Calculate amount based on current price per share.
        amount = (shares * totalUnderlying) / totalShares;
        totalShares -= shares;
        totalUnderlying -= amount;
        require(token.transfer(receiver, amount), "Token transfer failed");
        return amount;
    }

    /// @notice Returns the current price per share, scaled by 1e18.
    function pricePerShare() external view override returns (uint256) {
        if (totalShares == 0) return SCALE;
        return (totalUnderlying * SCALE) / totalShares;
    }

    /// @notice Simulates yield accrual by increasing the vault’s underlying balance.
    /// @param extraAmount The additional underlying tokens (yield) to add.
    function simulateYield(uint256 extraAmount) external {
        // In a real vault, yield might be accrued automatically.
        // Here we simply add extra tokens to totalUnderlying.
        totalUnderlying += extraAmount;
    }
}
