// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.4;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev DieselToken is LP token for Gearbox pools
contract DieselToken is ERC20, Ownable {
    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_)
    {
        _setupDecimals(decimals_);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address to, uint256 amount) external onlyOwner {
        _burn(to, amount);
    }
}
