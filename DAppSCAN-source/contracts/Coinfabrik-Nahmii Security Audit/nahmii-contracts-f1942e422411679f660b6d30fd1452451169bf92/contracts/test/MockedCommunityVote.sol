/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */
pragma solidity ^0.4.25;

/**
 * @title MockedCommunityVote
 * @notice Mocked implementation of community vote contract
 */
contract MockedCommunityVote {
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    bool[] public doubleSpenderWalletStats;
    uint256 public doubleSpenderWalletStatsIndex;
    uint256 public maxDriipNonce;
    uint256 public maxNullNonce;
    bool public dataAvailable;

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor() public {
        _reset();
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    function _reset()
    public
    {
        maxDriipNonce = 0;
        maxNullNonce = 0;
        dataAvailable = true;
        doubleSpenderWalletStats.length = 0;
        doubleSpenderWalletStatsIndex = 0;
    }

    function addDoubleSpenderWallet(bool doubleSpender)
    public
    returns (address[3])
    {
        doubleSpenderWalletStats.push(doubleSpender);
    }

    function isDoubleSpenderWallet(address)
    public
    returns (bool)
    {
        return doubleSpenderWalletStats.length == 0 ? false : doubleSpenderWalletStats[doubleSpenderWalletStatsIndex++];
    }

    function setMaxDriipNonce(uint256 _maxDriipNonce)
    public
    returns (uint256)
    {
        return maxDriipNonce = _maxDriipNonce;
    }

    function getMaxDriipNonce()
    public
    view
    returns (uint256)
    {
        return maxDriipNonce;
    }

    function setMaxNullNonce(uint256 _maxNullNonce)
    public
    returns (uint256)
    {
        return maxNullNonce = _maxNullNonce;
    }

    function getMaxNullNonce()
    public
    view
    returns (uint256)
    {
        return maxNullNonce;
    }

    function setDataAvailable(bool _dataAvailable)
    public
    returns (bool)
    {
        return dataAvailable = _dataAvailable;
    }

    function isDataAvailable()
    public
    view
    returns (bool)
    {
        return dataAvailable;
    }
}