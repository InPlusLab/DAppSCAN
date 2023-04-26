// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IDCL{
    function setUpdateOperator(uint256 assetId,address operator) external;
}