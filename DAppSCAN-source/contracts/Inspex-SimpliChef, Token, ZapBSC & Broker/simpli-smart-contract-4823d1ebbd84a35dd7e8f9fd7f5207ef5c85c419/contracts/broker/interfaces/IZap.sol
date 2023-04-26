// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IZap {
    function zapOut(address _from, uint amount) external;
    function zapIn(address _to) external payable returns (uint256, uint256, uint256);
    function zapInToken(address _from, uint amount, address _to) external returns (uint256, uint256, uint256);
    function zapOutToToken(address _from, uint256 amount, address _to) external returns (uint256);
}
