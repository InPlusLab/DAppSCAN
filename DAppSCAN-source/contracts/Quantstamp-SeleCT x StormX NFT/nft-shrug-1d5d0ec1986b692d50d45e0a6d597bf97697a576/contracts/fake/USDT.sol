// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDT is ERC20 {
    constructor() ERC20("Tether USD", "USDT") {
        _mint(msg.sender, 26916147047969263);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
