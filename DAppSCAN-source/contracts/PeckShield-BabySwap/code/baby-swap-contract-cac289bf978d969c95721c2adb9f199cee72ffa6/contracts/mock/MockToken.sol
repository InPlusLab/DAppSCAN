// SPDX-License-Identifier: MIT

pragma solidity >=0.7.4;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "hardhat/console.sol";

contract MockToken is ERC20, Ownable {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        if (decimals_ != 18) {
            _setupDecimals(decimals_);
        }
    }

    function mint (address to_, uint amount_) public {
        _mint(to_, amount_);
    }
}
