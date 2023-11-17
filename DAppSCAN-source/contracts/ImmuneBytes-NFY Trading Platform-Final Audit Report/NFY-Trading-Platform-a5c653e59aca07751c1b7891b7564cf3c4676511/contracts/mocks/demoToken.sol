//"SPDX-License-Identifier: UNLICENSED"

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Demo is ERC20  {

    constructor() public ERC20("DEMO", "DMT") {
        _mint(_msgSender(), 100000 * (10 ** uint256(decimals())));
    }

    function faucet(address to, uint amount) external {
        _mint(to, amount);
    }
}