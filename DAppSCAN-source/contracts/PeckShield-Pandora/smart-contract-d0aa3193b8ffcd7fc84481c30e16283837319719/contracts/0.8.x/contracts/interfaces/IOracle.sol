// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;
pragma experimental ABIEncoderV2;

interface IOracle {
    function consult() external view returns (uint256);
}
