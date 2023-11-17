/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

/**
 * @title MockedBalanceTracker
 * @notice Mocked implementation of balance tracker contract
 */
contract MockedBalanceTracker {
    //
    // Constants
    // -----------------------------------------------------------------------------------------------------------------
    string constant public DEPOSITED_BALANCE_TYPE = "deposited";
    string constant public SETTLED_BALANCE_TYPE = "settled";
    string constant public STAGED_BALANCE_TYPE = "staged";

    //
    // Types
    // -----------------------------------------------------------------------------------------------------------------
    struct LogEntry {
        int256 amount;
        uint256 blockNumber;
    }

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    bytes32 public depositedBalanceType;
    bytes32 public settledBalanceType;
    bytes32 public stagedBalanceType;

    mapping(bytes32 => uint256) private _logSizeByType;
    bytes32[] private _logSizeTypes;
    mapping(bytes32 => bool) private _logSizeTypeSetByType;

    mapping(bytes32 => LogEntry) private _lastLogByType;
    bytes32[] private _lastLogTypes;
    mapping(bytes32 => bool) private _lastLogTypeSetByType;

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor()
    public
    {
        depositedBalanceType = keccak256(abi.encodePacked(DEPOSITED_BALANCE_TYPE));
        settledBalanceType = keccak256(abi.encodePacked(SETTLED_BALANCE_TYPE));
        stagedBalanceType = keccak256(abi.encodePacked(STAGED_BALANCE_TYPE));
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    function _reset()
    public
    {
        uint256 i;
        for (i = 0; i < _logSizeTypes.length; i++)
            _logSizeByType[_logSizeTypes[i]] = 0;
        _logSizeTypes.length = 0;

        for (i = 0; i < _lastLogTypes.length; i++) {
            _lastLogByType[_lastLogTypes[i]].amount = 0;
            _lastLogByType[_lastLogTypes[i]].blockNumber = 0;
        }
        _lastLogTypes.length = 0;
    }

    function fungibleRecordsCount(address, bytes32 _type, address, uint256)
    public
    view
    returns (uint256)
    {
        return _logSizeByType[_type];
    }

    function _setLogSize(bytes32 _type, uint256 size)
    public
    {
        _logSizeByType[_type] = size;
        if (!_logSizeTypeSetByType[_type]) {
            _logSizeTypeSetByType[_type] = true;
            _logSizeTypes.push(_type);
        }
    }

    function lastFungibleRecord(address, bytes32 _type, address, uint256)
    public
    view
    returns (int256 amount, uint256 blockNumber)
    {
        amount = _lastLogByType[_type].amount;
        blockNumber = _lastLogByType[_type].blockNumber;
    }

    function _setLastLog(bytes32 _type, int256 amount, uint256 blockNumber)
    public
    {
        _lastLogByType[_type].amount = amount;
        _lastLogByType[_type].blockNumber = blockNumber;

        if (!_lastLogTypeSetByType[_type]) {
            _lastLogTypeSetByType[_type] = true;
            _lastLogTypes.push(_type);
        }
    }
}