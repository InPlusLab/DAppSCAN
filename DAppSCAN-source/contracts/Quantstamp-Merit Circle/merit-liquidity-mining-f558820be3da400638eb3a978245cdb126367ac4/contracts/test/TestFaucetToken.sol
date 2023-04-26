// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestFaucetToken is ERC20 {

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        //silence
    }

    function drip() external {
        _mint(msg.sender, 1000000 ether);
    }
}