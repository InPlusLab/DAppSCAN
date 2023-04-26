pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

// mint, burn inside
contract ERC20Mock is ERC20PresetMinterPauser {
    constructor(string memory _name, string memory _symbol)
        ERC20PresetMinterPauser(_name, _symbol)
    {}
}