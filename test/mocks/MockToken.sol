//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    uint8 decimals_;

    constructor(
        string memory symbol, 
        uint8 decimals__
    ) ERC20("Mock Token", symbol) {
        decimals_ = decimals__;
    }

    // decimals returns the number of decimals.
    function decimals() public view override returns (uint8) {
        return decimals_;
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}

