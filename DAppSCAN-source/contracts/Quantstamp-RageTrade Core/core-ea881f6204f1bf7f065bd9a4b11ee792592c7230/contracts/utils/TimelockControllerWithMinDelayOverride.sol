// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { TimelockController } from '@openzeppelin/contracts/governance/TimelockController.sol';

/// @title Timelock controller with a minimum delay override for certain functions
contract TimelockControllerWithMinDelayOverride is TimelockController {
    uint256 private _minDelayOverridePlusOne;
    mapping(bytes32 => uint256) private _minDelayOverridesPlusOne;

    event MinDelayOverrideSet(address target, bytes4 selector, uint256 newMinDelay);
    event MinDelayOverrideUnset(address target, bytes4 selector);

    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors
    ) TimelockController(minDelay, proposers, executors) {}

    function setMinDelayOverride(
        address target,
        bytes4 selector,
        uint256 minDelayOverride
    ) public {
        require(msg.sender == address(this), 'TimelockController: caller must be timelock');
        _minDelayOverridesPlusOne[_getKey(target, selector)] = minDelayOverride + 1;
        emit MinDelayOverrideSet(target, selector, minDelayOverride);
    }

    function unsetMinDelayOverride(address target, bytes4 selector) public {
        require(msg.sender == address(this), 'TimelockController: caller must be timelock');
        delete _minDelayOverridesPlusOne[_getKey(target, selector)];
        emit MinDelayOverrideUnset(target, selector);
    }

    function getMinDelayOverride(address target, bytes4 selector) external view returns (uint256 minDelayOverride) {
        uint256 minDelayOverridePlusOne = _minDelayOverridesPlusOne[_getKey(target, selector)];
        require(minDelayOverridePlusOne > 0, 'TimelockController: minDelayOverride not set');
        return minDelayOverridePlusOne - 1;
    }

    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual override onlyRole(PROPOSER_ROLE) {
        if (data.length >= 4) {
            uint256 minDelayOverridePlusOne = _minDelayOverridesPlusOne[_getKey(target, _getSelector(data))];
            if (minDelayOverridePlusOne != 0) {
                _minDelayOverridePlusOne = minDelayOverridePlusOne; // SSTORE
            }
        }
        super.schedule(target, value, data, predecessor, salt, delay);
        delete _minDelayOverridePlusOne;
    }

    function getMinDelay() public view virtual override returns (uint256 duration) {
        uint256 minDelayOverridePlusOne = _minDelayOverridePlusOne;
        return minDelayOverridePlusOne == 0 ? super.getMinDelay() : minDelayOverridePlusOne - 1;
    }

    function _getSelector(bytes calldata data) internal pure returns (bytes4 selector) {
        assert(data.length >= 4);
        assembly {
            // clear first memory word
            mstore(0, 0)
            // copy calldata to memory scratch space
            calldatacopy(0, data.offset, 4)
            // load memory to stack
            selector := mload(0)
        }
    }

    function _getKey(address target, bytes4 selector) internal pure returns (bytes32 c) {
        assembly {
            // store a in the last 20 bytes and b in the 4 bytes before
            c := xor(target, selector)
        }
    }
}
