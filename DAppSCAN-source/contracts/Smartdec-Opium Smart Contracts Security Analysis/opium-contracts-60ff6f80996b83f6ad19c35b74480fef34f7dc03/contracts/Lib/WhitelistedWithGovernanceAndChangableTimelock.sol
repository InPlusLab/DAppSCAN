pragma solidity ^0.5.4;

import "./WhitelistedWithGovernance.sol";

/// @notice Opium.Lib.WhitelistedWithGovernanceAndChangableTimelock contract implements Opium.Lib.WhitelistedWithGovernance and adds possibility for governor to change timelock interval within timelock interval
contract WhitelistedWithGovernanceAndChangableTimelock is WhitelistedWithGovernance {
    // Emitted when new timelock is proposed
    event Proposed(uint256 timelock);
    // Emitted when new timelock is committed (set)
    event Committed(uint256 timelock);

    // Timestamp of last timelock proposal
    uint256 timelockProposalTime = 0;
    // Proposed timelock
    uint256 proposedTimelock = 0;

    /// @notice Calling this function governor could propose new timelock
    /// @param _timelock uint256 New timelock value
    function proposeTimelock(uint256 _timelock) public onlyGovernor {
        timelockProposalTime = now;
        proposedTimelock = _timelock;
        emit Proposed(_timelock);
    }

    /// @notice Calling this function governor could commit previously proposed new timelock if timelock interval of proposal was passed
    function commitTimelock() public onlyGovernor {
        // Check if proposal was made
        require(timelockProposalTime != 0, "Didn't proposed yet");
        // Check if timelock interval was passed
        require((timelockProposalTime + TIME_LOCK_INTERVAL) < now, "Can't commit yet");
        
        // Set new timelock and emit event
        TIME_LOCK_INTERVAL = proposedTimelock;
        emit Committed(proposedTimelock);

        // Reset timelock time lock
        timelockProposalTime = 0;
    }
}
