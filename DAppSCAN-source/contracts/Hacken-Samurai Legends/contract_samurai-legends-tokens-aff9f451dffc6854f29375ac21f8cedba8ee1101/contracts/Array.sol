// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
@title Array
@author Leo
@notice Adds utility functions to an array of integers
*/
library Array {
    /**
    @notice Removes an array item by index
    @dev This is a O(1) time-complexity algorithm without persiting the order
    @param array A reference value to the array
    @param index An item index to be removed 
    */
    function remove(uint[] storage array, uint index) internal {
        require(index < array.length, "Index out of bound.");
        array[index] = array[array.length - 1];
        array.pop();
    }
}