// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IEdenToken.sol";
import "../interfaces/IVault.sol";
import "../interfaces/ITokenRegistry.sol";

/// @notice App metadata storage
struct AppStorage {
    // A record of states for signing / validating signatures
    mapping (address => uint) nonces;

    // Eden token
    IEdenToken edenToken;

    // Voting Power owner
    address owner;
    
    // lockManager contract
    address lockManager;

    // Token registry contract
    ITokenRegistry tokenRegistry;
}

/// @notice A checkpoint for marking number of votes from a given block
struct Checkpoint {
    uint32 fromBlock;
    uint256 votes;
}

/// @notice All storage variables related to checkpoints
struct CheckpointStorage {
     // A record of vote checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) checkpoints;

    // The number of checkpoints for each account
    mapping (address => uint32) numCheckpoints;
}

/// @notice The amount of a given token that has been staked, and the resulting voting power
struct Stake {
    uint256 amount;
    uint256 votingPower;
}

/// @notice All storage variables related to staking
struct StakeStorage {
    // Official record of staked balances for each account > token > stake
    mapping (address => mapping (address => Stake)) stakes;
}

library VotingPowerStorage {
    bytes32 constant VOTING_POWER_APP_STORAGE_POSITION = keccak256("voting.power.app.storage");
    bytes32 constant VOTING_POWER_CHECKPOINT_STORAGE_POSITION = keccak256("voting.power.checkpoint.storage");
    bytes32 constant VOTING_POWER_STAKE_STORAGE_POSITION = keccak256("voting.power.stake.storage");
    
    /**
     * @notice Load app storage struct from specified VOTING_POWER_APP_STORAGE_POSITION
     * @return app AppStorage struct
     */
    function appStorage() internal pure returns (AppStorage storage app) {        
        bytes32 position = VOTING_POWER_APP_STORAGE_POSITION;
        assembly {
            app.slot := position
        }
    }

    /**
     * @notice Load checkpoint storage struct from specified VOTING_POWER_CHECKPOINT_STORAGE_POSITION
     * @return cs CheckpointStorage struct
     */
    function checkpointStorage() internal pure returns (CheckpointStorage storage cs) {        
        bytes32 position = VOTING_POWER_CHECKPOINT_STORAGE_POSITION;
        assembly {
            cs.slot := position
        }
    }

    /**
     * @notice Load stake storage struct from specified VOTING_POWER_STAKE_STORAGE_POSITION
     * @return ss StakeStorage struct
     */
    function stakeStorage() internal pure returns (StakeStorage storage ss) {        
        bytes32 position = VOTING_POWER_STAKE_STORAGE_POSITION;
        assembly {
            ss.slot := position
        }
    }
}