// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;


contract MockOracle{
    function consult() external view returns (uint256) {
        return 1e6;
    }
}
