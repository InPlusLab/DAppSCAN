//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract MockERC20 is ERC20PresetFixedSupply {
    constructor() ERC20PresetFixedSupply("Token", "TKN", 1e27, msg.sender) {}
}
