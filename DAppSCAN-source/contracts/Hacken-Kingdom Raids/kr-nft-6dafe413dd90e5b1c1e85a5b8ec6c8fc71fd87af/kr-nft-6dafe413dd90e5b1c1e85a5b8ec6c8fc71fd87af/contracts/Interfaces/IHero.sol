// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IHero {
    function mintWithSummon(address _to) external returns (uint256);
    function mint(address to) external returns (uint256);
}
