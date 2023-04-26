// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
@title Generatable
@author Leo
@notice Generates a unique id
*/
contract Generatable {
    uint private id;

    /**
    @notice Generates a unique id
    @return id The newly generated id
    */
    function unique() internal returns (uint) {
        id += 1;
        return id;
    }
}