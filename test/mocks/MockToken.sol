//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
  uint8 decimals_;

  constructor(
    string memory name__,
    string memory symbol__,
    uint8 decimals__
  ) ERC20(name__, symbol__) {
    decimals_ = decimals__;
  }

  // decimals returns the number of decimals.
  function decimals() public view override returns (uint8) {
    return decimals_;
  }

  function mint(uint256 amount) public {
    _mint(msg.sender, amount);
  }
}
