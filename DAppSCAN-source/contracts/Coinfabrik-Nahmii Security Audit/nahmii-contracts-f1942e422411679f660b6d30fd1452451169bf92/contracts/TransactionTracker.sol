/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {Ownable} from "./Ownable.sol";
import {Servable} from "./Servable.sol";

/**
 * @title Transaction tracker
 * @notice An ownable to track transactions of generic types
 */
contract TransactionTracker is Ownable, Servable {

    //
    // Structures
    // -----------------------------------------------------------------------------------------------------------------
    struct TransactionRecord {
        int256 value;
        uint256 blockNumber;
        address currencyCt;
        uint256 currencyId;
    }

    struct TransactionLog {
        TransactionRecord[] records;
        mapping(address => mapping(uint256 => uint256[])) recordIndicesByCurrency;
    }

    //
    // Constants
    // -----------------------------------------------------------------------------------------------------------------
    string constant public DEPOSIT_TRANSACTION_TYPE = "deposit";
    string constant public WITHDRAWAL_TRANSACTION_TYPE = "withdrawal";

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    bytes32 public depositTransactionType;
    bytes32 public withdrawalTransactionType;

    mapping(address => mapping(bytes32 => TransactionLog)) private transactionLogByWalletType;

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer)
    public
    {
        depositTransactionType = keccak256(abi.encodePacked(DEPOSIT_TRANSACTION_TYPE));
        withdrawalTransactionType = keccak256(abi.encodePacked(WITHDRAWAL_TRANSACTION_TYPE));
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Add a transaction record of the given wallet, type, value and currency
    /// @param wallet The address of the concerned wallet
    /// @param _type The transaction type
    /// @param value The concerned value (amount of fungible, id of non-fungible)
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function add(address wallet, bytes32 _type, int256 value, address currencyCt,
        uint256 currencyId)
    public
    onlyActiveService
    {
        transactionLogByWalletType[wallet][_type].records.length++;

        uint256 index = transactionLogByWalletType[wallet][_type].records.length - 1;

        transactionLogByWalletType[wallet][_type].records[index].value = value;
        transactionLogByWalletType[wallet][_type].records[index].blockNumber = block.number;
        transactionLogByWalletType[wallet][_type].records[index].currencyCt = currencyCt;
        transactionLogByWalletType[wallet][_type].records[index].currencyId = currencyId;

        transactionLogByWalletType[wallet][_type].recordIndicesByCurrency[currencyCt][currencyId].push(index);
    }

    /// @notice Get the number of transaction records for the given wallet and type
    /// @param wallet The address of the concerned wallet
    /// @param _type The transaction type
    /// @return The count of transaction records
    function count(address wallet, bytes32 _type)
    public
    view
    returns (uint256)
    {
        return transactionLogByWalletType[wallet][_type].records.length;
    }

    /// @notice Get the transaction record for the given wallet and type by the given index
    /// @param wallet The address of the concerned wallet
    /// @param _type The transaction type
    /// @param index The concerned log index
    /// @return The transaction record
    function getByIndex(address wallet, bytes32 _type, uint256 index)
    public
    view
    returns (int256 value, uint256 blockNumber, address currencyCt, uint256 currencyId)
    {
        TransactionRecord storage entry = transactionLogByWalletType[wallet][_type].records[index];
        value = entry.value;
        blockNumber = entry.blockNumber;
        currencyCt = entry.currencyCt;
        currencyId = entry.currencyId;
    }

    /// @notice Get the transaction record for the given wallet and type by the given block number
    /// @param wallet The address of the concerned wallet
    /// @param _type The transaction type
    /// @param _blockNumber The concerned block number
    /// @return The transaction record
    function getByBlockNumber(address wallet, bytes32 _type, uint256 _blockNumber)
    public
    view
    returns (int256 value, uint256 blockNumber, address currencyCt, uint256 currencyId)
    {
        return getByIndex(wallet, _type, _indexByBlockNumber(wallet, _type, _blockNumber));
    }

    /// @notice Get the number of transaction records for the given wallet, type and currency
    /// @param wallet The address of the concerned wallet
    /// @param _type The transaction type
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The count of transaction records
    function countByCurrency(address wallet, bytes32 _type, address currencyCt,
        uint256 currencyId)
    public
    view
    returns (uint256)
    {
        return transactionLogByWalletType[wallet][_type].recordIndicesByCurrency[currencyCt][currencyId].length;
    }

    /// @notice Get the transaction record for the given wallet, type and currency by the given index
    /// @param wallet The address of the concerned wallet
    /// @param _type The transaction type
    /// @param index The concerned log index
    /// @return The transaction record
    function getByCurrencyIndex(address wallet, bytes32 _type, address currencyCt,
        uint256 currencyId, uint256 index)
    public
    view
    returns (int256 value, uint256 blockNumber)
    {
        uint256 entryIndex = transactionLogByWalletType[wallet][_type].recordIndicesByCurrency[currencyCt][currencyId][index];

        TransactionRecord storage entry = transactionLogByWalletType[wallet][_type].records[entryIndex];
        value = entry.value;
        blockNumber = entry.blockNumber;
    }

    /// @notice Get the transaction record for the given wallet, type and currency by the given block number
    /// @param wallet The address of the concerned wallet
    /// @param _type The transaction type
    /// @param _blockNumber The concerned block number
    /// @return The transaction record
    function getByCurrencyBlockNumber(address wallet, bytes32 _type, address currencyCt,
        uint256 currencyId, uint256 _blockNumber)
    public
    view
    returns (int256 value, uint256 blockNumber)
    {
        return getByCurrencyIndex(
            wallet, _type, currencyCt, currencyId,
            _indexByCurrencyBlockNumber(
                wallet, _type, currencyCt, currencyId, _blockNumber
            )
        );
    }

    //
    // Private functions
    // -----------------------------------------------------------------------------------------------------------------
    function _indexByBlockNumber(address wallet, bytes32 _type, uint256 blockNumber)
    private
    view
    returns (uint256)
    {
        require(0 < transactionLogByWalletType[wallet][_type].records.length);
        for (uint256 i = transactionLogByWalletType[wallet][_type].records.length - 1; i >= 0; i--)
            if (blockNumber >= transactionLogByWalletType[wallet][_type].records[i].blockNumber)
                return i;
        revert();
    }

    function _indexByCurrencyBlockNumber(address wallet, bytes32 _type, address currencyCt,
        uint256 currencyId, uint256 blockNumber)
    private
    view
    returns (uint256)
    {
        require(0 < transactionLogByWalletType[wallet][_type].recordIndicesByCurrency[currencyCt][currencyId].length);
        for (uint256 i = transactionLogByWalletType[wallet][_type].recordIndicesByCurrency[currencyCt][currencyId].length - 1; i >= 0; i--) {
            uint256 j = transactionLogByWalletType[wallet][_type].recordIndicesByCurrency[currencyCt][currencyId][i];
            if (blockNumber >= transactionLogByWalletType[wallet][_type].records[j].blockNumber)
                return j;
        }
        revert();
    }
}