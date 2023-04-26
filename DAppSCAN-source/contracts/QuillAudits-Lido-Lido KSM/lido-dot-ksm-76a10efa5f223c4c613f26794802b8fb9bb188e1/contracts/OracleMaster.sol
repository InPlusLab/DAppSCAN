// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/IOracle.sol";
import "../interfaces/ILido.sol";
import "../interfaces/ILedger.sol";
import "../interfaces/IAuthManager.sol";

import "./utils/LedgerUtils.sol";

contract OracleMaster is Pausable {
    using Clones for address;
    using LedgerUtils for Types.OracleData;

    event MemberAdded(address member);
    event MemberRemoved(address member);
    event QuorumChanged(uint8 QUORUM);

    // current era id
    uint64 public eraId;

    // Oracle members
    address[] public members;

    // ledger -> oracle pairing
    mapping(address => address) private oracleForLedger;


    // address of oracle clone template contract
    address public ORACLE_CLONE;

    // Lido smart contract
    address public LIDO;

    // Quorum threshold
    uint8 public QUORUM;

    // Relay genesis timestamp
    uint64 public RELAY_GENESIS_TIMESTAMP;

    // Relay seconds per era
    uint64 public RELAY_SECONDS_PER_ERA;


    /// Maximum number of oracle committee members
    uint256 public constant MAX_MEMBERS = 255;

    // Missing member index
    uint256 internal constant MEMBER_NOT_FOUND = type(uint256).max;

    // General oracle manager role
    bytes32 internal constant ROLE_ORACLE_MANAGER = keccak256("ROLE_ORACLE_MANAGER");

    // Oracle members manager role
    bytes32 internal constant ROLE_ORACLE_MEMBERS_MANAGER = keccak256("ROLE_ORACLE_MEMBERS_MANAGER");

    // Oracle members manager role
    bytes32 internal constant ROLE_ORACLE_QUORUM_MANAGER = keccak256("ROLE_ORACLE_QUORUM_MANAGER");


    modifier auth(bytes32 role) {
        require(IAuthManager(ILido(LIDO).AUTH_MANAGER()).has(role, msg.sender), "OM: UNAUTHOROZED");
        _;
    }

    modifier onlyLido() {
        require(msg.sender == LIDO, "OM: CALLER_NOT_LIDO");
        _;
    }


    /**
    * @notice Initialize oracle master contract, allowed to call only once
    * @param _oracleClone oracle clone contract address
    * @param _quorum inital quorum threshold
    */
    function initialize(
        address _oracleClone,
        uint8 _quorum
    ) external {
        require(ORACLE_CLONE == address(0), "OM: ALREADY_INITIALIZED");

        ORACLE_CLONE = _oracleClone;
        QUORUM = _quorum;
    }

    /**
    * @notice Set lido contract address, allowed to only once
    * @param _lido lido contract address
    */
    function setLido(address _lido) external {
        require(LIDO == address(0), "OM: LIDO_ALREADY_DEFINED");
        LIDO = _lido;
    }

    /**
    * @notice Set relaychain params required for oracles, allowed to call only by lido contract
    * @param _relayGenesisTs relaychain genesis timestamp
    * @param _relaySecondsPerEra relaychain era duratation in seconds
    */
    function setRelayParams(uint64 _relayGenesisTs, uint64 _relaySecondsPerEra) external onlyLido {
        RELAY_GENESIS_TIMESTAMP = _relayGenesisTs;
        RELAY_SECONDS_PER_ERA = _relaySecondsPerEra;
    }

    /**
    * @notice Set the number of exactly the same reports needed to finalize the era
              allowed to call only by ROLE_ORACLE_QUORUM_MANAGER
    * @param _quorum new value of quorum threshold
    */
    function setQuorum(uint8 _quorum) external auth(ROLE_ORACLE_QUORUM_MANAGER) {
        require(0 != _quorum, "OM: QUORUM_WONT_BE_MADE");
        uint8 oldQuorum = QUORUM;
        QUORUM = _quorum;

        // If the QUORUM value lowered, check existing reports whether it is time to push
        if (oldQuorum > _quorum) {
            address[] memory ledgers = ILido(LIDO).getLedgerAddresses();
            uint256 _length = ledgers.length;
            for (uint256 i = 0; i < _length; ++i) {
                address oracle = oracleForLedger[ledgers[i]];
                if (oracle != address(0)) {
                    IOracle(oracle).softenQuorum(_quorum, eraId);
                }
            }
        }
        emit QuorumChanged(_quorum);
    }

    /**
    * @notice Return oracle contract for the given ledger
    * @param  _ledger ledger contract address
    * @return linked oracle address
    */
    function getOracle(address _ledger) external view returns (address) {
        return oracleForLedger[_ledger];
    }

    /**
    * @notice Return current Era according to relay chain spec
    * @return current era id
    */
    function getCurrentEraId() public view returns (uint64) {
        return _getCurrentEraId();
    }

    /**
    * @notice Return relay chain stash account addresses
    * @return Array of bytes32 relaychain stash accounts
    */
    function getStashAccounts() external view returns (bytes32[] memory) {
        return ILido(LIDO).getStashAccounts();
    }

    /**
    * @notice Return last reported era and oracle is already reported indicator
    * @param _oracleMember - oracle member address
    * @param _stash - stash account id
    * @return lastEra - last reported era
    * @return isReported - true if oracle member already reported for given stash, else false
    */
    function isReportedLastEra(address _oracleMember, bytes32 _stash)
        external
        view
        returns (
            uint64 lastEra,
            bool isReported
        )
    {
        uint64 lastEra = eraId;

        uint256 memberIdx = _getMemberId(_oracleMember);
        if (memberIdx == MEMBER_NOT_FOUND) {
            return (lastEra, false);
        }

        address ledger = ILido(LIDO).findLedger(_stash);
        if (ledger == address(0)) {
            return (lastEra, false);
        }

        return (lastEra, IOracle(oracleForLedger[ledger]).isReported(memberIdx));
    }

    /**
    * @notice Stop pool routine operations (reportRelay), allowed to call only by ROLE_ORACLE_MANAGER
    */
    function pause() external auth(ROLE_ORACLE_MANAGER) {
        _pause();
    }

    /**
    * @notice Resume pool routine operations (reportRelay), allowed to call only by ROLE_ORACLE_MANAGER
    */
    function resume() external auth(ROLE_ORACLE_MANAGER) {
        _unpause();
    }

    /**
    * @notice Add new member to the oracle member committee list, allowed to call only by ROLE_ORACLE_MEMBERS_MANAGER
    * @param _member proposed member address
    */
    function addOracleMember(address _member) external auth(ROLE_ORACLE_MEMBERS_MANAGER) {
        require(address(0) != _member, "OM: BAD_ARGUMENT");
        require(MEMBER_NOT_FOUND == _getMemberId(_member), "OM: MEMBER_EXISTS");
        require(members.length < 254, "OM: MEMBERS_TOO_MANY");

        members.push(_member);
        require(members.length < MAX_MEMBERS, "OM: TOO_MANY_MEMBERS");
        emit MemberAdded(_member);
    }

    /**
    * @notice Remove `_member` from the oracle member committee list, allowed to call only by ROLE_ORACLE_MEMBERS_MANAGER
    */
    function removeOracleMember(address _member) external auth(ROLE_ORACLE_MEMBERS_MANAGER) {
        uint256 index = _getMemberId(_member);
        require(index != MEMBER_NOT_FOUND, "OM: MEMBER_NOT_FOUND");
        uint256 last = members.length - 1;
        if (index != last) members[index] = members[last];
        members.pop();
        emit MemberRemoved(_member);

        // delete the data for the last eraId, let remained oracles report it again
        _clearReporting();
    }

    /**
    * @notice Add ledger to oracle set, allowed to call only by lido contract
    * @param _ledger Ledger contract
    */
    function addLedger(address _ledger) external onlyLido {
        require(ORACLE_CLONE != address(0), "OM: ORACLE_CLONE_UNINITIALIZED");
        IOracle newOracle = IOracle(ORACLE_CLONE.cloneDeterministic(bytes32(uint256(uint160(_ledger)) << 96)));
        newOracle.initialize(address(this), _ledger);
        oracleForLedger[_ledger] = address(newOracle);
    }

    /**
    * @notice Remove ledger from oracle set, allowed to call only by lido contract
    * @param _ledger ledger contract
    */
    function removeLedger(address _ledger) external onlyLido {
        oracleForLedger[_ledger] = address(0);
    }

    /**
    * @notice Accept oracle committee member reports from the relay side
    * @param _eraId relaychain era
    * @param _report relaychain data report
    */
    function reportRelay(uint64 _eraId, Types.OracleData calldata _report) external whenNotPaused {
        require(_report.isConsistent(), "OM: INCORRECT_REPORT");

        uint256 memberIndex = _getMemberId(msg.sender);
        require(memberIndex != MEMBER_NOT_FOUND, "OM: MEMBER_NOT_FOUND");

        address ledger = ILido(LIDO).findLedger(_report.stashAccount);
        address oracle = oracleForLedger[ledger];
        require(oracle != address(0), "OM: ORACLE_FOR_LEDGER_NOT_FOUND");
        require(_eraId >= eraId, "OM: ERA_TOO_OLD");

        // new era
        if (_eraId > eraId) {
            require(_eraId <= _getCurrentEraId(), "OM: UNEXPECTED_NEW_ERA");
            eraId = _eraId;
            _clearReporting();
            ILido(LIDO).flushStakes();
        }

        IOracle(oracle).reportRelay(memberIndex, QUORUM, _eraId, _report);
    }

    /**
    * @notice Return oracle instance index in the member array
    * @param _member member address
    * @return member index
    */
    function _getMemberId(address _member) internal view returns (uint256) {
        uint256 length = members.length;
        for (uint256 i = 0; i < length; ++i) {
            if (members[i] == _member) {
                return i;
            }
        }
        return MEMBER_NOT_FOUND;
    }

    /**
    * @notice Calculate current expected era id
    * @dev Calculation based on relaychain genesis timestamp and era duratation
    * @return current era id
    */
    function _getCurrentEraId() internal view returns (uint64) {
        return (uint64(block.timestamp) - RELAY_GENESIS_TIMESTAMP ) / RELAY_SECONDS_PER_ERA;
    }

    /**
    * @notice Delete interim data for current Era, free storage memory for each oracle
    */
    function _clearReporting() internal {
        address[] memory ledgers = ILido(LIDO).getLedgerAddresses();
        uint256 _length = ledgers.length;
        for (uint256 i = 0; i < _length; ++i) {
            address oracle = oracleForLedger[ledgers[i]];
            if (oracle != address(0)) {
                IOracle(oracle).clearReporting();
            }
        }
    }
}
