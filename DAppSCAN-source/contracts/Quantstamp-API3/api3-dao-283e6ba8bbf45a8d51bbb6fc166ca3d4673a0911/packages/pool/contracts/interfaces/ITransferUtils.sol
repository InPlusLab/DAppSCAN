//SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./IDelegationUtils.sol";

interface ITransferUtils is IDelegationUtils{
    event Deposited(
        address indexed user,
        uint256 amount
        );

    event Withdrawn(
        address indexed user,
        address indexed destination,
        uint256 amount
        );

    function deposit(
        address source,
        uint256 amount,
        address userAddress
        )
        external;

    function withdraw(
        address destination,
        uint256 amount
        )
        external;
}
