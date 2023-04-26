// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVotingPowerFormula {
    function convertTokensToVotingPower(uint256 amount) external view returns (uint256);
}