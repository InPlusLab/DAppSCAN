pragma solidity ^0.5.4;

import "./Whitelisted.sol";

/// @title Opium.Lib.WhitelistedWithGovernance contract implements Opium.Lib.Whitelisted and adds governance for whitelist controlling
contract WhitelistedWithGovernance is Whitelisted {
    // Emitted when new governor is set
    event GovernorSet(address governor);

    // Emitted when new whitelist is proposed
    event Proposed(address[] whitelist);
    // Emitted when proposed whitelist is committed (set)
    event Committed(address[] whitelist);

    // Proposal life timelock interval
    uint256 public TIME_LOCK_INTERVAL;

    // Governor address
    address public governor;

    // Contract initialization flag
    bool public initialized = false;

    // Timestamp of last proposal
    uint256 public proposalTime = 0;
    // Proposed whitelist
    address[] public proposedWhitelist;

    /// @notice This modifier restricts access to functions, which could be called only by governor
    modifier onlyGovernor() {
        require(msg.sender == governor, "Only governor allowed");
        _;
    }

    /// @notice Contract constructor
    /// @param _timeLockInterval uint256 Initial value for timelock interval
    /// @param _governor address Initial value for governor
    constructor(uint256 _timeLockInterval, address _governor) public {
        TIME_LOCK_INTERVAL = _timeLockInterval;
        governor = _governor;
        emit GovernorSet(governor);
    }

    /// @notice Calling this function governor could propose new whitelist addresses array. Also it allows to initialize first whitelist if it was not initialized yet.
    function proposeWhitelist(address[] memory _whitelist) public onlyGovernor {
        // Restrict empty proposals
        require(_whitelist.length != 0, "Can't be empty");

        // If whitelist has never been initialized, we set whitelist right away without proposal
        if (!initialized) {
            initialized = true;
            whitelist = _whitelist;
            emit Committed(whitelist);

        // Otherwise save current time as timestamp of proposal, save proposed whitelist and emit event
        } else {
            proposalTime = now;
            proposedWhitelist = _whitelist;
            emit Proposed(proposedWhitelist);
        }
    }

    /// @notice Calling this function governor commits proposed whitelist if timelock interval of proposal was passed
    function commitWhitelist() public onlyGovernor {
        // Check if proposal was made
        require(proposalTime != 0, "Didn't proposed yet");

        // Check if timelock interval was passed
        require((proposalTime + TIME_LOCK_INTERVAL) < now, "Can't commit yet");
        
        // Set new whitelist and emit event
        whitelist = proposedWhitelist;
        emit Committed(whitelist);

        // Reset proposal time lock
        proposalTime = 0;
    }

    /// @notice This function allows governor to transfer governance to a new governor and emits event
    /// @param _governor address Address of new governor
    function setGovernor(address _governor) public onlyGovernor {
        governor = _governor;
        emit GovernorSet(governor);
    }
}
