/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

/**
 * @title MockedWalletLocker
 * @notice Mocked implementation of wallet locker contract
 */
contract MockedWalletLocker {
    //
    // Types
    // -----------------------------------------------------------------------------------------------------------------
    struct LockUnlock {
        address lockedWallet;
        address lockerWallet;
    }

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    LockUnlock[] public locks;
    LockUnlock[] public unlocks;

    bool public locked;
    bool public lockedBy;
    int256 public _lockedAmount;
    uint256 public _lockedIdsCount;
    int256[] public _lockedIdsByIndices;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event LockByProxyEvent(address lockedWallet, address lockerWallet);
    event UnlockByProxyEvent(address lockedWallet, address lockerWallet);

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    function _reset()
    public
    {
        locks.length = 0;
        unlocks.length = 0;
        locked = false;
        lockedBy = false;
        _lockedAmount = 0;
        _lockedIdsCount = 0;
        _lockedIdsByIndices.length = 0;
    }

    function lockByProxy(address lockedWallet, address lockerWallet)
    public
    {
        locks.push(LockUnlock(lockedWallet, lockerWallet));
        emit LockByProxyEvent(lockedWallet, lockerWallet);
    }

    function unlockByProxy(address wallet)
    public
    {
        unlocks.push(LockUnlock(wallet, address(0)));
        emit UnlockByProxyEvent(wallet, address(0));
    }

    function lockedWalletsCount()
    public
    view
    returns (uint256)
    {
        return locks.length;
    }

    function _unlocksCount()
    public
    view
    returns (uint256)
    {
        return unlocks.length;
    }

    function isLocked(address, address, uint256)
    public
    view
    returns (bool)
    {
        return locked;
    }

    function _setLocked(bool _locked)
    public
    {
        locked = _locked;
    }

    function isLockedBy(address, address, address, uint256)
    public
    view
    returns (bool)
    {
        return lockedBy;
    }

    function _setLockedBy(bool _lockedBy)
    public
    {
        lockedBy = _lockedBy;
    }

    function lockedAmount(address, address, address, uint256)
    public
    view
    returns (int256)
    {
        return _lockedAmount;
    }

    function _setLockedAmount(int256 amount)
    public
    {
        _lockedAmount = amount;
    }

    function lockedIdsCount(address, address, address, uint256)
    public
    view
    returns (uint256)
    {
        return _lockedIdsCount;
    }

    function _setLockedIdsCount(uint256 count)
    public
    {
        _lockedIdsCount = count;
    }

    function lockedIdsByIndices(address, address, address, uint256, uint256, uint256)
    public
    view
    returns (int256[])
    {
        return _lockedIdsByIndices;
    }

    function _setLockedIdsByIndices(int256[] ids)
    public
    {
        _lockedIdsByIndices = ids;
    }
}