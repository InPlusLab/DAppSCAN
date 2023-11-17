// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BNPLToken is ERC20, AccessControl {
    constructor() ERC20("BNPL", "BNPL") {
        _mint(msg.sender, 100000000 * (10**18));
    }
}
