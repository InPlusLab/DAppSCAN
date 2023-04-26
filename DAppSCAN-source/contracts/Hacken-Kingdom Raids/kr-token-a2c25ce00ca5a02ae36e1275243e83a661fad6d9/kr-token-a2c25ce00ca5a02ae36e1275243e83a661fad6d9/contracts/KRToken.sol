// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract KRToken is ERC20, Ownable {
    constructor() ERC20("Kingdom Raids Token", "KRS") {
        _mint(msg.sender, 1e9 * 1e18);
    }
}
