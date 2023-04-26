// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// N:B: Mock contract for testing purposes only
contract MockERC20 is ERC20("Mock", "MCK") {
    constructor() {
        _mint(msg.sender, 5_000_000 * 10 ** 18);
    }
}
