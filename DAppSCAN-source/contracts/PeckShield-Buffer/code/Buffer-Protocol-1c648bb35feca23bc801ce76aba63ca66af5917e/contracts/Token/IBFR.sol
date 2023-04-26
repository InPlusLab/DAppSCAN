// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @author Heisenberg
 * @title Buffer iBFR Token
 * @notice The central token to the Buffer ecosystem
 */
contract IBFR is ERC20("iBuffer Token", "iBFR") {
    constructor() {
        uint256 INITIAL_SUPPLY = 100 * 10**6 * 10**decimals();
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
