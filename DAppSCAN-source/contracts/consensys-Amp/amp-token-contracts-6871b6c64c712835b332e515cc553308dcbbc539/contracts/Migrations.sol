// SPDX-License-Identifier: MIT

pragma solidity >=0.4.25 <0.7.0;


/**
 * @title Migrations
 * @notice Migrations logic.
 */
contract Migrations {
    /**
     * @notice Contract owner.
     */
    address public owner;

    /**
     * @notice Last completed migration.
     */
    uint256 public last_completed_migration;

    /**
     * @notice Initialize Migrations.
     */
    constructor() public {
        owner = msg.sender;
    }

    /**
     * @notice Restriction modifier.
     */
    modifier restricted() {
        if (msg.sender == owner) _;
    }

    /**
     * @notice Set last completed migration.
     * @param completed Last completed migration.
     */
    function setCompleted(uint256 completed) public restricted {
        last_completed_migration = completed;
    }
}
