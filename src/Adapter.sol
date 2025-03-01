// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract Adapter {
    function deposit(address vault, uint256 amount) public virtual;
    function withdraw(address vault, uint256 amount) public virtual;
    function pricePerShare(address vault) public view virtual returns (uint256);
    function refreshSetup(address token, address vault) public virtual {
        IERC20(token).approve(vault, type(uint256).max);
    }
}

interface BeefyVault {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _shares) external;
    function pricePerShare() external view returns (uint256);
}

contract BeefyAdapter is Adapter {
    function deposit(address vault, uint256 amount) public override {
        BeefyVault(vault).deposit(amount);
    }

    function withdraw(address vault, uint256 amount) public override {
        BeefyVault(vault).withdraw(amount);
    }

    function pricePerShare(address vault) public view override returns (uint256) {
        return BeefyVault(vault).pricePerShare();
    }
}
