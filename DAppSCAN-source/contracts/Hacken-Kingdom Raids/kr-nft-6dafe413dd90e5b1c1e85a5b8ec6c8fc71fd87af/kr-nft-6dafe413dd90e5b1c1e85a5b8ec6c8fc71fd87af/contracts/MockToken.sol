// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20, Ownable {

    constructor(
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
    }

    function mint(address to, uint256 value) external onlyOwner {
        super._mint(to, value);
    }

    function burn(address to, uint256 value) external onlyOwner {
        super._burn(to, value);
    }
}
