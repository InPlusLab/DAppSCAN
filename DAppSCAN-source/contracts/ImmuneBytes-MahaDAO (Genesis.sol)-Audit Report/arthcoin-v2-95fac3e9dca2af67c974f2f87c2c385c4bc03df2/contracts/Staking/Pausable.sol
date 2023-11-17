// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from '../access/Ownable.sol';

/// Refer: https://docs.synthetix.io/contracts/Pausable
abstract contract Pausable is Ownable {
    /**
     * State variables.
     */

    bool public paused;
    uint256 public lastPauseTime;

    /**
     * Event.
     */
    event PauseChanged(bool isPaused);

    /**
     * Modifier.
     */
    modifier notPaused {
        require(
            !paused,
            'Pausable: This action cannot be performed while the contract is paused'
        );
        _;
    }

    /**
     * Constructor.
     */
    constructor() {
        // This contract is abstract, and thus cannot be instantiated directly
        require(owner() != address(0), 'Owner must be set');
        // Paused will be false, and lastPauseTime will be 0 upon initialisation
    }

    /**
     * External.
     */

    /**
     * @notice Change the paused state of the contract
     * @dev Only the contract owner may call this.
     */
    function setPaused(bool _paused) external onlyOwner {
        // Ensure we're actually changing the state before we do anything
        if (_paused == paused) {
            return;
        }

        // Set our paused state.
        paused = _paused;

        // If applicable, set the last pause time.
        if (paused) {
            lastPauseTime = block.timestamp;
        }

        // Let everyone know that our pause state has changed.
        emit PauseChanged(paused);
    }
}
