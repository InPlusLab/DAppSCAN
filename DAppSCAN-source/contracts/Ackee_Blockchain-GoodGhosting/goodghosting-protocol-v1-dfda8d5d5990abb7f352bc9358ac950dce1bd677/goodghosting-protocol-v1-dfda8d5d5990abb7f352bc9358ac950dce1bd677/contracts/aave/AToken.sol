// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.11;

interface AToken {
    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);
}
