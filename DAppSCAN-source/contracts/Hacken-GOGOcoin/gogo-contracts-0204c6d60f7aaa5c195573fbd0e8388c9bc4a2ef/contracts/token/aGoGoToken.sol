// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract aGoGoToken is ERC20Burnable, Ownable {
    constructor() ERC20("Alpha GOGO", "aGOGO") {
        _mint(owner(), 20000000 * (10**decimals())); //20M
    }
}
