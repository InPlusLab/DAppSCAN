// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

interface IGoGoNFTOracle {
    function getBoostMultiplyer(uint256 tier)
        external
        view
        returns (uint256 multiplyer);
}
