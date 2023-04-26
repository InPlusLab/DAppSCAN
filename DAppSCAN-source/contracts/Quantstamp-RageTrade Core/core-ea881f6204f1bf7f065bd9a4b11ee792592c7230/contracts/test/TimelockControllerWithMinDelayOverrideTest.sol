// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import { TimelockControllerWithMinDelayOverride } from '../utils/TimelockControllerWithMinDelayOverride.sol';

import 'hardhat/console.sol';

contract TimelockControllerWithMinDelayOverrideTest is TimelockControllerWithMinDelayOverride {
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors
    ) TimelockControllerWithMinDelayOverride(minDelay, proposers, executors) {}

    // replicate similar calldata like in schedule function
    function getSelector(
        address,
        uint256,
        bytes calldata data,
        bytes32,
        bytes32,
        uint256
    ) public pure returns (bytes4 selector) {
        bytes32 m1_before;
        bytes32 m2_before;
        bytes32 m3_before;
        assembly {
            m1_before := mload(0x20)
            m2_before := mload(0x40)
            m3_before := mload(0x60)
        }

        selector = _getSelector(data);

        bytes32 m1_after;
        bytes32 m2_after;
        bytes32 m3_after;
        assembly {
            m1_after := mload(0x20)
            m2_after := mload(0x40)
            m3_after := mload(0x60)
        }

        // ensuring that _getSelector didn't screw up memory past m0
        assert(m1_before == m1_after);
        assert(m2_before == m2_after);
        assert(m3_before == m3_after);
    }

    function getKey(address target, bytes4 selector) public pure returns (bytes32 c) {
        return _getKey(target, selector);
    }
}
