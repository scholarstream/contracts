// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Mock is IERC20 {
  function mint(address to, uint256 amount) external;
}

contract MockYieldVault {
  IERC20 public token;
  uint256 public totalUnderlying;
  uint256 public totalShares;
  uint256 public constant SCALE = 1e18;

  constructor(address _token) {
    token = IERC20(_token);
  }

  /// @notice Deposits tokens into the vault.
  /// If there are no shares yet, shares = amount; otherwise shares = (amount * totalShares) / totalUnderlying.
  function deposit(uint256 amount) external returns (uint256 shares) {
    require(
      token.transferFrom(msg.sender, address(this), amount),
      "Transfer failed"
    );
    if (totalShares == 0 || totalUnderlying == 0) {
      shares = amount;
    } else {
      shares = (amount * totalShares) / totalUnderlying;
    }
    totalUnderlying += amount;
    totalShares += shares;
  }

  /// @notice Withdraws tokens by redeeming a given number of shares.
  function withdraw(uint256 shares) external returns (uint256 redeemed) {
    require(shares <= totalShares, "Not enough shares");
    redeemed = (shares * totalUnderlying) / totalShares;
    totalShares -= shares;
    totalUnderlying -= redeemed;
    require(token.transfer(msg.sender, redeemed), "Token transfer failed");
  }

  /// @notice Returns the current price per share (scaled by 1e18).
  function getPricePerShare() external view returns (uint256) {
    if (totalShares == 0) return SCALE;
    return (totalUnderlying * SCALE) / totalShares;
  }

  // helper for tests: simulate yield by minting tokens
  function simulateYield(uint256 amount) external {
    totalUnderlying += amount;
    IERC20Mock(address(token)).mint(address(this), amount);
  }
}
