// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IGovernance.sol";
import "./lib/AccessControlEnumerable.sol";
import "./lib/BytesLib.sol";

/**
 * @title DistributorGovernance
 * @dev Add or remove block producers from the network and set rewards collectors
 */
contract DistributorGovernance is AccessControlEnumerable, IGovernance {
    using BytesLib for bytes;

    /// @notice Admin governance role
    bytes32 public constant GOV_ROLE = keccak256("GOV_ROLE");

    /// @notice Admin delegator role
    bytes32 public constant DELEGATOR_ROLE = keccak256("DELEGATOR_ROLE");

    /// @notice Mapping of block producer to reward collector
    mapping (address => address) public override rewardCollector;

    /// @notice Whitelisted block producers
    mapping (address => bool) public override blockProducer;

    /// @dev Packed struct containing rewards distribution details
    bytes private _rewardSchedule;

    /// @notice Length of single rewards schedule entry
    uint256 public constant REWARD_SCHEDULE_ENTRY_LENGTH = 32;

    /// @notice Only Governance modifier
    modifier onlyGov() {
        require(hasRole(GOV_ROLE, msg.sender), "must be gov");
        _;
    }

    /// @notice Only addresses with delegator role
    modifier onlyDelegator() {
        require(hasRole(DELEGATOR_ROLE, msg.sender), "must be delegator");
        _;
    }

    /// @notice Only addresses with delegator role or block producer
    modifier onlyDelegatorOrProducer(address producer) {
        require(hasRole(DELEGATOR_ROLE, msg.sender) || msg.sender == producer, "must be producer or delegator");
        _;
    }

    /** 
     * @notice Construct a new DistributorGovernance contract
     * @param _admin Governance admin
     * @param _blockProducers Initial whitelist of block producers
     * @param _collectors Initial reward collectors for block producers
     */
    constructor(
        address _admin, 
        address[] memory _blockProducers,
        address[] memory _collectors
    ) {
        require(_blockProducers.length == _collectors.length, "length mismatch");
        _setupRole(GOV_ROLE, _admin);
        _setupRole(DELEGATOR_ROLE, _admin);
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        for(uint i; i< _blockProducers.length; i++) {
            blockProducer[_blockProducers[i]] = true;
            emit BlockProducerAdded(_blockProducers[i]);

            rewardCollector[_blockProducers[i]] = _collectors[i];
            emit BlockProducerRewardCollectorChanged(_blockProducers[i], _collectors[i]);
        }
    }

    /**
     * @notice Add block producer to the network
     * @dev Only governance can call
     * @param producer Block producer address
     */
    function add(address producer) external onlyGov {
        require(blockProducer[producer] == false, "already block producer");
        blockProducer[producer] = true;
        emit BlockProducerAdded(producer);
    }

    /**
     * @notice Add batch of block producers to network
     * @dev Only governance can call
     * @param producers List of block producers
     */
    function addBatch(address[] memory producers) external onlyGov {
        for(uint i; i< producers.length; i++) {
            require(blockProducer[producers[i]] == false, "already block producer");
            blockProducer[producers[i]] = true;
            emit BlockProducerAdded(producers[i]);
        }
    }

    /**
     * @notice Remove block producer from network
     * @dev Only governance can call
     * @param producer Block producer address
     */
    function remove(address producer) external onlyGov {
        require(blockProducer[producer] == true, "not block producer");
        blockProducer[producer] = false;
        emit BlockProducerRemoved(producer);
    }

    /**
     * @notice Remove batch of block producers from network
     * @dev Only governance can call
     * @param producers List of block producers
     */    
    function removeBatch(address[] memory producers) external onlyGov {
        for(uint i; i< producers.length; i++) {
            require(blockProducer[producers[i]] == true, "not block producer");
            blockProducer[producers[i]] = false;
            emit BlockProducerRemoved(producers[i]);
        }
    }

    /**
     * @notice Delegate a collector address that can claim rewards on behalf of a block producer
     * @dev Only delegator admin or block producer can call
     * @param producer Block producer address
     * @param collector Collector address
     */
    function delegate(address producer, address collector) external onlyDelegatorOrProducer(producer) {
        rewardCollector[producer] = collector;
        emit BlockProducerRewardCollectorChanged(producer, collector);
    }

    /**
     * @notice Delegate collector addresses that can claim rewards on behalf of block producers in batch
     * @dev Only delegator admin can call
     * @param producers Block producer addresses
     * @param collectors Collector addresses
     */
    function delegateBatch(address[] memory producers, address[] memory collectors) external onlyDelegator {
        require(producers.length == collectors.length, "length mismatch");
        // SWC-113-DoS with Failed Call: L143 - L146
        for(uint i; i< producers.length; i++) {
            rewardCollector[producers[i]] = collectors[i];
            emit BlockProducerRewardCollectorChanged(producers[i], collectors[i]);
        }
    }

    /**
     * @notice Set reward schedule
     * @dev Only governance can call
     * @param set Packed bytes representing reward schedule
     */
    function setRewardSchedule(bytes memory set) onlyGov public {
        _rewardSchedule = set;
        emit RewardScheduleChanged();
    }

    /**
     * @notice Get reward schedule entry
     * @param index Index location
     * @return Rewards schedule entry
     */
    function rewardScheduleEntry(uint256 index) public override view returns (RewardScheduleEntry memory) {
        RewardScheduleEntry memory entry;
        uint256 start = index * REWARD_SCHEDULE_ENTRY_LENGTH;
        entry.startTime = _rewardSchedule.toUint64(start);
        entry.epochDuration = _rewardSchedule.toUint64(start + 8);
        entry.rewardsPerEpoch = _rewardSchedule.toUint128(start + 16);
        return entry;
    }

    /**
     * @notice Get all reward schedule entries
     * @return Number of rewards schedule entries
     */
    function rewardScheduleEntries() public override view returns (uint256) {
        return _rewardSchedule.length / REWARD_SCHEDULE_ENTRY_LENGTH;
    }
}
