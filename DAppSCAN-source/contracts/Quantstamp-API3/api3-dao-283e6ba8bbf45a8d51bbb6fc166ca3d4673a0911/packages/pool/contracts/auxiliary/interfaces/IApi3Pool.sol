//SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IApi3Pool {
    function deposit(
        address source,
        uint256 amount,
        address userAddress
        )
        external;

    function depositWithVesting(
        address source,
        uint256 amount,
        address userAddress,
        uint256 releaseStart,
        uint256 releaseEnd
        )
        external;
}
