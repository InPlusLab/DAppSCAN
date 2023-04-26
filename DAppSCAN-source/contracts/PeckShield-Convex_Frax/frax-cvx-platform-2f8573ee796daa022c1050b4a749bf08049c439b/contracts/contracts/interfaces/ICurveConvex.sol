// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface ICurveConvex {
   function earmarkRewards(uint256 _pid) external returns(bool);
   function earmarkFees() external returns(bool);
}