/**
 * COPYRIGHT © 2020 RARI CAPITAL, INC. ALL RIGHTS RESERVED.
 * Anyone is free to integrate the public APIs (described in `API.md` of the `rari-contracts` package) of the official smart contract instances deployed by Rari Capital, Inc. in any application (commercial or noncommercial and under any license) benefitting Rari Capital, Inc.
 * Only those with explicit permission from a co-founder of Rari Capital (Jai Bhavnani, Jack Lipstone, or David Lucid) are permitted to study, review, or analyze any part of the source code contained in the `rari-contracts` package.
 * Reuse (including deployment of smart contracts other than private testing on a private network), modification, redistribution, or sublicensing of any source code contained in the `rari-contracts` package is not permitted without the explicit permission of David Lucid of Rari Capital, Inc.
 * No one is permitted to use the software for any purpose other than those allowed by this license.
 * This license is liable to change at any time at the sole discretion of David Lucid of Rari Capital, Inc.
 */

pragma solidity ^0.5.7;
pragma experimental ABIEncoderV2;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor () internal { }
    // solhint-disable-previous-line no-empty-blocks

    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(isOwner(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Returns true if the caller is the current owner.
     */
    function isOwner() public view returns (bool) {
        return _msgSender() == _owner;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     */
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/**
 * @title DummyRariFundManager
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @dev This contract is a dummy upgrade of RariFundManager for testing.
 */
contract DummyRariFundManager is Ownable {
    /**
     * @dev Old RariFundManager contract authorized to migrate its data to the new one.
     */
    address private _authorizedFundManagerDataSource;

    /**
     * @dev Upgrades RariFundManager.
     * Authorizes the source for fund manager data (i.e., the old fund manager).
     * @param authorizedFundManagerDataSource Authorized source for data (i.e., the old fund manager).
     */
    function authorizeFundManagerDataSource(address authorizedFundManagerDataSource) external onlyOwner {
        _authorizedFundManagerDataSource = authorizedFundManagerDataSource;
    }

    /**
     * @dev Struct for data to transfer from the old RariFundManager to the new one.
     */
    struct FundManagerData {
        int256 netDeposits;
        int256 rawInterestAccruedAtLastFeeRateChange;
        int256 interestFeesGeneratedAtLastFeeRateChange;
        uint256 interestFeesClaimed;
    }

    /**
     * @dev Upgrades RariFundManager.
     * Sets data receieved from the old contract.
     * @param data The data from the old contract necessary to initialize the new contract.
     */
    function setFundManagerData(FundManagerData calldata data) external {
        require(_authorizedFundManagerDataSource != address(0) && msg.sender == _authorizedFundManagerDataSource, "Caller is not an authorized source.");
        
        _netDeposits = data.netDeposits;
        _rawInterestAccruedAtLastFeeRateChange = data.rawInterestAccruedAtLastFeeRateChange;
        _interestFeesGeneratedAtLastFeeRateChange = data.interestFeesGeneratedAtLastFeeRateChange;
        _interestFeesClaimed = data.interestFeesClaimed;
    }

    /**
     * @dev Net quantity of deposits to the fund (i.e., deposits - withdrawals).
     * On deposit, amount deposited is added to _netDeposits; on withdrawal, amount withdrawn is subtracted from _netDeposits.
     */
    int256 private _netDeposits;

    /**
     * @dev The amount of interest accrued at the time of the most recent change to the fee rate.
     */
    int256 private _rawInterestAccruedAtLastFeeRateChange;

    /**
     * @dev The amount of fees generated on interest at the time of the most recent change to the fee rate.
     */
    int256 private _interestFeesGeneratedAtLastFeeRateChange;

    /**
     * @dev The total claimed amount of interest fees.
     */
    uint256 private _interestFeesClaimed;
}
