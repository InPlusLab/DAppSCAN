// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

abstract contract Roles is Ownable {
    address public operatorAddress;
    address public governorAddress;

    event AssignGovernorAddress(address indexed _address);
    event AssignOperatorAddress(address indexed _address);

    constructor() {}

    modifier onlyOperator() {
        require(
            msg.sender == operatorAddress,
            "Only operator allowed."
        );
        _;
    }

    modifier onlyGovernor() {
        require(
            msg.sender == governorAddress,
            "Only governor allowed."
        );
        _;
    }

    function setOperatorAddress(address _operator) external onlyOwner {
        require(_operator != address(0), "Cannot assign 0x0");
        operatorAddress = _operator;
        emit AssignOperatorAddress(_operator);
    }

    function setGovernorAddress(address _governor) external onlyOwner {
        require(_governor != address(0), "Cannot assign 0x0");
        governorAddress = _governor;
        emit AssignGovernorAddress(_governor);
    }
}
