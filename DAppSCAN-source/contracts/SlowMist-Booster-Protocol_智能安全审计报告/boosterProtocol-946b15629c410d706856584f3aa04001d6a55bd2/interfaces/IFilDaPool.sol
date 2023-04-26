// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IFilDaPool {

    // 查询各种池子信息
    function claimComp(address holder) external;
    function claimComp(address holder, address[] memory cTokens) external;
    function claimComp(address[] memory holders, address[] memory cTokens, bool borrowers, bool suppliers) external;
}