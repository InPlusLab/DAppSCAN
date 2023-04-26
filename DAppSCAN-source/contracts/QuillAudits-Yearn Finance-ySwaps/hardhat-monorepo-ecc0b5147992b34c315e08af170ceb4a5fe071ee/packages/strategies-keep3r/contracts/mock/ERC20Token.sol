// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Token is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _mintAmount
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, _mintAmount);
    }
}
