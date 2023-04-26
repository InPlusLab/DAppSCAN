// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

/// Tempus Token with a fixed supply and holders having the ability to burn their own tokens.
contract TempusToken is ERC20PresetFixedSupply {
    /// @param totalTokenSupply total supply of the token, initially awarded to msg.sender
    constructor(uint256 totalTokenSupply) ERC20PresetFixedSupply("Tempus", "TEMP", totalTokenSupply, msg.sender) {}
}
