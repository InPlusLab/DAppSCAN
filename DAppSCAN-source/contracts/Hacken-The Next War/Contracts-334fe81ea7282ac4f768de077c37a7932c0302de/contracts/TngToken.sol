// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TngToken is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address wallet
    ) ERC20 (name, symbol) {
        _mint(wallet, totalSupply * (10 ** decimals()));
    }

}