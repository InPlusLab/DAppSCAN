// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.0;

import {ERC20} from "../../dependencies/openzeppelin/token/ERC20/ERC20.sol";

/**
 * @title ERC20Mintable
 * @dev ERC20 minting logic
 */
contract MintableERC20 is ERC20 {

    constructor(string memory name_, string memory symbol_) ERC20(name_,symbol_) {
    }

    /**
     * @dev Function to mint tokens
     * @param value The amount of tokens to mint.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(uint256 value) public returns (bool) {
        _mint(msg.sender, value);
        return true;
    }
}