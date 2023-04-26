// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title An ERC20 token to be used when testing a pool
/// @dev Don't use this for anything real. There's no access controls on mint and burn.
contract TestToken is ERC20 {
    uint8 internal _decimals = 18;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(uint256 amount, address account) external returns (bool) {
        _mint(account, amount);
        return true;
    }

    function burn(uint256 amount, address account) external returns (bool) {
        _burn(account, amount);
        return true;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setDecimals(uint8 newDecimals) external {
        _decimals = newDecimals;
    }
}
