// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SamuraiLegends is ERC20 {
    constructor() ERC20("SamuraiLegends", "SMG") {
        _mint(msg.sender, 600_000_000 * 1e9);
    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }
}