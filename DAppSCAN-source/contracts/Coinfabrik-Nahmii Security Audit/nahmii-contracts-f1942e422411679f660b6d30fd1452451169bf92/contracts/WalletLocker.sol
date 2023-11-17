/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {Ownable} from "./Ownable.sol";
import {Configurable} from "./Configurable.sol";
import {AuthorizableServable} from "./AuthorizableServable.sol";
import {SafeMathUintLib} from "./SafeMathUintLib.sol";

/**
 * @title Wallet locker
 * @notice An ownable to lock and unlock wallets
 */
contract WalletLocker is Ownable, Configurable, AuthorizableServable {
    using SafeMathUintLib for uint256;

    //
    // Structures
    // -----------------------------------------------------------------------------------------------------------------
    struct FungibleLock {
        address locker;
        int256 amount;
        uint256 unlockTime;
    }

    struct NonFungibleLock {
        address locker;
        int256[] ids;
        uint256 unlockTime;
    }

    struct Wallet {
        mapping(address => mapping(uint256 => FungibleLock[])) fungibleLocksMap;
        mapping(address => mapping(uint256 => mapping(address => uint256))) fungibleLockIndexMap;

        mapping(address => mapping(uint256 => NonFungibleLock[])) nonFungibleLocksMap;
        mapping(address => mapping(uint256 => mapping(address => uint256))) nonFungibleLockIndexMap;
    }

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    //    mapping(address => mapping(address => mapping(uint256 => FungibleLock[]))) public fungibleLocksMap;
    //    mapping(address => mapping(address => mapping(uint256 => mapping(address => uint256)))) public fungibleLockIndexMap;
    //
    //    mapping(address => mapping(address => mapping(uint256 => NonFungibleLock[]))) public nonFungibleLocksMap;
    //    mapping(address => mapping(address => mapping(uint256 => mapping(address => uint256)))) public nonFungibleLockIndexMap;

    mapping(address => Wallet) private walletMap;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event LockFungibleByProxyEvent(address lockedWallet, address lockerWallet, int256 amount,
        address currencyCt, uint256 currencyId);
    event LockNonFungibleByProxyEvent(address lockedWallet, address lockerWallet, int256[] ids,
        address currencyCt, uint256 currencyId);
    event UnlockFungibleEvent(address lockedWallet, address lockerWallet, int256 amount, address currencyCt,
        uint256 currencyId);
    event UnlockFungibleByProxyEvent(address lockedWallet, address lockerWallet, int256 amount, address currencyCt,
        uint256 currencyId);
    event UnlockNonFungibleEvent(address lockedWallet, address lockerWallet, int256[] ids, address currencyCt,
        uint256 currencyId);
    event UnlockNonFungibleByProxyEvent(address lockedWallet, address lockerWallet, int256[] ids, address currencyCt,
        uint256 currencyId);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer)
    public
    {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------

    /// @notice Lock the given locked wallet's fungible amount of currency on behalf of the given locker wallet
    /// @param lockedWallet The address of wallet that will be locked
    /// @param lockerWallet The address of wallet that locks
    /// @param amount The amount to be locked
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function lockFungibleByProxy(address lockedWallet, address lockerWallet, int256 amount,
        address currencyCt, uint256 currencyId)
    public
    onlyAuthorizedService(lockedWallet)
    {
        // Require that locked and locker wallets are not identical
        require(lockedWallet != lockerWallet);

        uint256 lockIndex = walletMap[lockedWallet].fungibleLockIndexMap[currencyCt][currencyId][lockerWallet];

        // Require that there is no existing conflicting lock set
        require(
            0 == lockIndex ||
        block.timestamp >= walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId][lockIndex - 1].unlockTime
        );

        if (0 == lockIndex) {
            walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId].length++;
            lockIndex = walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId].length;
            walletMap[lockedWallet].fungibleLockIndexMap[currencyCt][currencyId][lockerWallet] = lockIndex;
        }

        // Lock and set release time
        walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId][lockIndex - 1].locker = lockerWallet;
        walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId][lockIndex - 1].amount = amount;
        walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId][lockIndex - 1].unlockTime = block.timestamp.add(configuration.walletLockTimeout());

        // Emit event
        emit LockFungibleByProxyEvent(lockedWallet, lockerWallet, amount, currencyCt, currencyId);
    }

    /// @notice Lock the given locked wallet's non-fungible IDs of currency on behalf of the given locker wallet
    /// @param lockedWallet The address of wallet that will be locked
    /// @param lockerWallet The address of wallet that locks
    /// @param ids The IDs to be locked
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function lockNonFungibleByProxy(address lockedWallet, address lockerWallet, int256[] ids,
        address currencyCt, uint256 currencyId)
    public
    onlyAuthorizedService(lockedWallet)
    {
        // Require that locked and locker wallets are not identical
        require(lockedWallet != lockerWallet);

        uint256 lockIndex = walletMap[lockedWallet].nonFungibleLockIndexMap[currencyCt][currencyId][lockerWallet];

        // Require that there is no existing conflicting lock set
        require(
            0 == lockIndex ||
        block.timestamp >= walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId][lockIndex - 1].unlockTime
        );

        if (0 == lockIndex) {
            walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId].length++;
            lockIndex = walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId].length;
            walletMap[lockedWallet].nonFungibleLockIndexMap[currencyCt][currencyId][lockerWallet] = lockIndex;
        }

        // Lock and set release time
        walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId][lockIndex - 1].locker = lockerWallet;
        walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId][lockIndex - 1].ids = ids;
        walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId][lockIndex - 1].unlockTime = block.timestamp.add(configuration.walletLockTimeout());

        // Emit event
        emit LockNonFungibleByProxyEvent(lockedWallet, lockerWallet, ids, currencyCt, currencyId);
    }

    /// @notice Unlock the given locked wallet's fungible amount of currency previously
    /// locked by the given locker wallet
    /// @param lockedWallet The address of the locked wallet
    /// @param lockerWallet The address of the locker wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function unlockFungible(address lockedWallet, address lockerWallet, address currencyCt, uint256 currencyId)
    public
    {
        uint256 lockIndex = walletMap[lockedWallet].fungibleLockIndexMap[currencyCt][currencyId][lockerWallet];
        if (0 == lockIndex)
            return;

        // Require that release timeout has expired
        require(
            block.timestamp >= walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId][lockIndex].unlockTime
        );

        // Unlock
        int256 amount = _unlockFungible(lockedWallet, lockerWallet, currencyCt, currencyId);

        // Emit event
        emit UnlockFungibleEvent(lockedWallet, lockerWallet, amount, currencyCt, currencyId);
    }

    /// @notice Unlock by proxy the given locked wallet's fungible amount of currency previously
    /// locked by the given locker wallet
    /// @param lockedWallet The address of the locked wallet
    /// @param lockerWallet The address of the locker wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function unlockFungibleByProxy(address lockedWallet, address lockerWallet, address currencyCt, uint256 currencyId)
    public
    onlyAuthorizedService(lockedWallet)
    {
        uint256 lockIndex = walletMap[lockedWallet].fungibleLockIndexMap[currencyCt][currencyId][lockerWallet];
        if (0 == lockIndex)
            return;

        // Unlock
        int256 amount = _unlockFungible(lockedWallet, lockerWallet, currencyCt, currencyId);

        // Emit event
        emit UnlockFungibleByProxyEvent(lockedWallet, lockerWallet, amount, currencyCt, currencyId);
    }

    /// @notice Unlock the given locked wallet's non-fungible IDs of currency previously
    /// locked by the given locker wallet
    /// @param lockedWallet The address of the locked wallet
    /// @param lockerWallet The address of the locker wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function unlockNonFungible(address lockedWallet, address lockerWallet, address currencyCt, uint256 currencyId)
    public
    {
        uint256 lockIndex = walletMap[lockedWallet].nonFungibleLockIndexMap[currencyCt][currencyId][lockerWallet];
        if (0 == lockIndex)
            return;

        // Require that release timeout has expired
        require(
            block.timestamp >= walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId][lockIndex].unlockTime
        );

        // Unlock
        int256[] memory ids = _unlockNonFungible(lockedWallet, lockerWallet, currencyCt, currencyId);

        // Emit event
        emit UnlockNonFungibleEvent(lockedWallet, lockerWallet, ids, currencyCt, currencyId);
    }

    /// @notice Unlock by proxy the given locked wallet's non-fungible IDs of currency previously
    /// locked by the given locker wallet
    /// @param lockedWallet The address of the locked wallet
    /// @param lockerWallet The address of the locker wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function unlockNonFungibleByProxy(address lockedWallet, address lockerWallet, address currencyCt, uint256 currencyId)
    public
    onlyAuthorizedService(lockedWallet)
    {
        uint256 lockIndex = walletMap[lockedWallet].nonFungibleLockIndexMap[currencyCt][currencyId][lockerWallet];
        if (0 == lockIndex)
            return;

        // Unlock
        int256[] memory ids = _unlockNonFungible(lockedWallet, lockerWallet, currencyCt, currencyId);

        // Emit event
        emit UnlockNonFungibleByProxyEvent(lockedWallet, lockerWallet, ids, currencyCt, currencyId);
    }

    /// @notice Get the fungible amount of the given currency held by locked wallet that is
    /// locked by locker wallet
    /// @param lockedWallet The address of the locked wallet
    /// @param lockerWallet The address of the locker wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function lockedAmount(address lockedWallet, address lockerWallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (int256)
    {
        uint256 lockIndex = walletMap[lockedWallet].fungibleLockIndexMap[currencyCt][currencyId][lockerWallet];
        if (0 == lockIndex)
            return 0;

        return walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId][lockIndex - 1].amount;
    }

    /// @notice Get the count of non-fungible IDs of the given currency held by locked wallet that is
    /// locked by locker wallet
    /// @param lockedWallet The address of the locked wallet
    /// @param lockerWallet The address of the locker wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function lockedIdsCount(address lockedWallet, address lockerWallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (uint256)
    {
        uint256 lockIndex = walletMap[lockedWallet].nonFungibleLockIndexMap[currencyCt][currencyId][lockerWallet];
        if (0 == lockIndex)
            return 0;

        return walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId][lockIndex - 1].ids.length;
    }

    /// @notice Get the set of non-fungible IDs of the given currency held by locked wallet that is
    /// locked by locker wallet and whose indices are in the given range of indices
    /// @param lockedWallet The address of the locked wallet
    /// @param lockerWallet The address of the locker wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param low The lower ID index
    /// @param up The upper ID index
    function lockedIdsByIndices(address lockedWallet, address lockerWallet, address currencyCt, uint256 currencyId,
        uint256 low, uint256 up)
    public
    view
    returns (int256[])
    {
        uint256 lockIndex = walletMap[lockedWallet].nonFungibleLockIndexMap[currencyCt][currencyId][lockerWallet];
        if (0 == lockIndex)
            return new int256[](0);

        NonFungibleLock storage lock = walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId][lockIndex - 1];

        if (0 == lock.ids.length)
            return new int256[](0);

        up = up.clampMax(lock.ids.length - 1);
        int256[] memory _ids = new int256[](up - low + 1);
        for (uint256 i = low; i <= up; i++)
            _ids[i - low] = lock.ids[i];

        return _ids;
    }

    /// @notice Gauge whether the given locked wallet and currency is locked
    /// @param lockedWallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return true if wallet/currency pair is locked, else false
    function isLocked(address lockedWallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (bool)
    {
        return (0 < walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId].length ||
        0 < walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId].length);
    }

    /// @notice Gauge whether the given locked wallet and currency is locked by the given locker wallet
    /// @param lockedWallet The address of the concerned locked wallet
    /// @param lockerWallet The address of the concerned locker wallet
    /// @return true if lockedWallet is locked by lockerWallet, else false
    function isLockedBy(address lockedWallet, address lockerWallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (bool)
    {
        return (0 < walletMap[lockedWallet].fungibleLockIndexMap[currencyCt][currencyId][lockerWallet] ||
        0 < walletMap[lockedWallet].nonFungibleLockIndexMap[currencyCt][currencyId][lockerWallet]);
    }

    //
    //
    // Private functions
    // -----------------------------------------------------------------------------------------------------------------
    function _unlockFungible(address lockedWallet, address lockerWallet, address currencyCt, uint256 currencyId)
    private
    returns (int256)
    {
        uint256 lockIndex = walletMap[lockedWallet].fungibleLockIndexMap[currencyCt][currencyId][lockerWallet];

        int256 amount = walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId][lockIndex - 1].amount;

//        if (lockIndex < walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId].length) {
//            walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId][lockIndex - 1] =
//            walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId][walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId].length - 1];
//
//            walletMap[lockedWallet].fungibleLockIndexMap[currencyCt][currencyId][walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId][lockIndex - 1].locker] = lockIndex;
//        }
        walletMap[lockedWallet].fungibleLocksMap[currencyCt][currencyId].length--;
        walletMap[lockedWallet].fungibleLockIndexMap[currencyCt][currencyId][lockerWallet] = 0;

        return amount;
    }

    function _unlockNonFungible(address lockedWallet, address lockerWallet, address currencyCt, uint256 currencyId)
    private
    returns (int256[])
    {
        uint256 lockIndex = walletMap[lockedWallet].nonFungibleLockIndexMap[currencyCt][currencyId][lockerWallet];

        int256[] memory ids = walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId][lockIndex - 1].ids;

        if (lockIndex < walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId].length) {
            walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId][lockIndex - 1] =
            walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId][walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId].length - 1];

            walletMap[lockedWallet].nonFungibleLockIndexMap[currencyCt][currencyId][walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId][lockIndex - 1].locker] = lockIndex;
        }
        walletMap[lockedWallet].nonFungibleLocksMap[currencyCt][currencyId].length--;
        walletMap[lockedWallet].nonFungibleLockIndexMap[currencyCt][currencyId][lockerWallet] = 0;

        return ids;
    }
}