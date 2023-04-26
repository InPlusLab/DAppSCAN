// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Vesting/VestingFactory.sol";
import "./VestingHarness.sol";

contract VestingFactoryHarness is VestingFactory {

    uint256 public blockTimestamp;

    constructor(address libraryAddress_) VestingFactory(libraryAddress_) {}


    function fastTimestamp(uint256 days_) public returns (uint256) {
        blockTimestamp += days_ * 24 * 60 * 60;
        return blockTimestamp;
    }

    function setBlockTimestamp(uint256 timestamp) public {
        blockTimestamp = timestamp;
    }

    function getBlockTimestamp() public override view returns (uint256) {
        return blockTimestamp;
    }


    function createVestingContract(IERC20 _token) external override {
        address _contract = Clones.createClone(libraryAddress);

        VestingHarness(_contract).initialize(msg.sender, _token);
        instances.push(Instance(_contract, msg.sender, address(_token)));

        emit InstanceCreated(_contract, msg.sender, address(_token));
    }
} 