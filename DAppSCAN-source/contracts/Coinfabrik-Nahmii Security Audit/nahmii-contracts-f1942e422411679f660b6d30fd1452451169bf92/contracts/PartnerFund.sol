/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import {SafeMathIntLib} from "./SafeMathIntLib.sol";
import {Ownable} from "./Ownable.sol";
import {Beneficiary} from "./Beneficiary.sol";
import {TransferControllerManageable} from "./TransferControllerManageable.sol";
import {TransferController} from "./TransferController.sol";
import {FungibleBalanceLib} from "./FungibleBalanceLib.sol";
import {TxHistoryLib} from "./TxHistoryLib.sol";
import {MonetaryTypesLib} from "./MonetaryTypesLib.sol";
import {Strings} from "solidity-util/lib/Strings.sol";

/**
 * @title PartnerFund
 * @notice Where partners’ fees are managed
 */
contract PartnerFund is Ownable, Beneficiary, TransferControllerManageable {
    using FungibleBalanceLib for FungibleBalanceLib.Balance;
    using TxHistoryLib for TxHistoryLib.TxHistory;
    using SafeMathIntLib for int256;
    using Strings for string;

    //
    // Structures
    // -----------------------------------------------------------------------------------------------------------------
    struct Partner {
        bytes32 nameHash;

        uint256 fee;
        address wallet;
        uint256 index;

        bool operatorCanUpdate;
        bool partnerCanUpdate;

        FungibleBalanceLib.Balance active;
        FungibleBalanceLib.Balance staged;

        TxHistoryLib.TxHistory txHistory;
        FullBalanceHistory[] fullBalanceHistory;
    }

    struct FullBalanceHistory {
        uint256 listIndex;
        int256 balance;
        uint256 blockNumber;
    }

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    Partner[] private partners;

    mapping(bytes32 => uint256) private _indexByNameHash;
    mapping(address => uint256) private _indexByWallet;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event ReceiveEvent(address from, int256 amount, address currencyCt, uint256 currencyId);
    event RegisterPartnerByNameEvent(string name, uint256 fee, address wallet);
    event RegisterPartnerByNameHashEvent(bytes32 nameHash, uint256 fee, address wallet);
    event SetFeeByIndexEvent(uint256 index, uint256 oldFee, uint256 newFee);
    event SetFeeByNameEvent(string name, uint256 oldFee, uint256 newFee);
    event SetFeeByNameHashEvent(bytes32 nameHash, uint256 oldFee, uint256 newFee);
    event SetFeeByWalletEvent(address wallet, uint256 oldFee, uint256 newFee);
    event SetPartnerWalletByIndexEvent(uint256 index, address oldWallet, address newWallet);
    event SetPartnerWalletByNameEvent(string name, address oldWallet, address newWallet);
    event SetPartnerWalletByNameHashEvent(bytes32 nameHash, address oldWallet, address newWallet);
    event SetPartnerWalletByWalletEvent(address oldWallet, address newWallet);
    event StageEvent(address from, int256 amount, address currencyCt, uint256 currencyId);
    event WithdrawEvent(address to, int256 amount, address currencyCt, uint256 currencyId);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) public {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Fallback function that deposits ethers
    function() public payable {
        _receiveEthersTo(
            indexByWallet(msg.sender) - 1, SafeMathIntLib.toNonZeroInt256(msg.value)
        );
    }

    /// @notice Receive ethers to
    /// @param tag The tag of the concerned partner
    function receiveEthersTo(address tag, string)
    public
    payable
    {
        _receiveEthersTo(
            uint256(tag) - 1, SafeMathIntLib.toNonZeroInt256(msg.value)
        );
    }

    /// @notice Receive tokens
    /// @param amount The concerned amount
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of token ("ERC20", "ERC721")
    function receiveTokens(string, int256 amount, address currencyCt,
        uint256 currencyId, string standard)
    public
    {
        _receiveTokensTo(
            indexByWallet(msg.sender) - 1, amount, currencyCt, currencyId, standard
        );
    }

    /// @notice Receive tokens to
    /// @param tag The tag of the concerned partner
    /// @param amount The concerned amount
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of token ("ERC20", "ERC721")
    function receiveTokensTo(address tag, string, int256 amount, address currencyCt,
        uint256 currencyId, string standard)
    public
    {
        _receiveTokensTo(
            uint256(tag) - 1, amount, currencyCt, currencyId, standard
        );
    }

    /// @notice Hash name
    /// @param name The name to be hashed
    /// @return The hash value
    function hashName(string name)
    public
    pure
    returns (bytes32)
    {
        return keccak256(abi.encodePacked(name.upper()));
    }

    /// @notice Get deposit by partner and deposit indices
    /// @param partnerIndex The index of the concerned partner
    /// @param depositIndex The index of the concerned deposit
    /// return The deposit parameters
    function depositByIndices(uint256 partnerIndex, uint256 depositIndex)
    public
    view
    returns (int256 balance, uint256 blockNumber, address currencyCt, uint256 currencyId)
    {
        // Require partner index is one of registered partner
        require(0 < partnerIndex && partnerIndex <= partners.length);

        return _depositByIndices(partnerIndex - 1, depositIndex);
    }

    /// @notice Get deposit by partner name and deposit indices
    /// @param name The name of the concerned partner
    /// @param depositIndex The index of the concerned deposit
    /// return The deposit parameters
    function depositByName(string name, uint depositIndex)
    public
    view
    returns (int256 balance, uint256 blockNumber, address currencyCt, uint256 currencyId)
    {
        // Implicitly require that partner name is registered
        return _depositByIndices(indexByName(name) - 1, depositIndex);
    }

    /// @notice Get deposit by partner name hash and deposit indices
    /// @param nameHash The hashed name of the concerned partner
    /// @param depositIndex The index of the concerned deposit
    /// return The deposit parameters
    function depositByNameHash(bytes32 nameHash, uint depositIndex)
    public
    view
    returns (int256 balance, uint256 blockNumber, address currencyCt, uint256 currencyId)
    {
        // Implicitly require that partner name hash is registered
        return _depositByIndices(indexByNameHash(nameHash) - 1, depositIndex);
    }

    /// @notice Get deposit by partner wallet and deposit indices
    /// @param wallet The wallet of the concerned partner
    /// @param depositIndex The index of the concerned deposit
    /// return The deposit parameters
    function depositByWallet(address wallet, uint depositIndex)
    public
    view
    returns (int256 balance, uint256 blockNumber, address currencyCt, uint256 currencyId)
    {
        // Implicitly require that partner wallet is registered
        return _depositByIndices(indexByWallet(wallet) - 1, depositIndex);
    }

    /// @notice Get deposits count by partner index
    /// @param index The index of the concerned partner
    /// return The deposits count
    function depositsCountByIndex(uint256 index)
    public
    view
    returns (uint256)
    {
        // Require partner index is one of registered partner
        require(0 < index && index <= partners.length);

        return _depositsCountByIndex(index - 1);
    }

    /// @notice Get deposits count by partner name
    /// @param name The name of the concerned partner
    /// return The deposits count
    function depositsCountByName(string name)
    public
    view
    returns (uint256)
    {
        // Implicitly require that partner name is registered
        return _depositsCountByIndex(indexByName(name) - 1);
    }

    /// @notice Get deposits count by partner name hash
    /// @param nameHash The hashed name of the concerned partner
    /// return The deposits count
    function depositsCountByNameHash(bytes32 nameHash)
    public
    view
    returns (uint256)
    {
        // Implicitly require that partner name hash is registered
        return _depositsCountByIndex(indexByNameHash(nameHash) - 1);
    }

    /// @notice Get deposits count by partner wallet
    /// @param wallet The wallet of the concerned partner
    /// return The deposits count
    function depositsCountByWallet(address wallet)
    public
    view
    returns (uint256)
    {
        // Implicitly require that partner wallet is registered
        return _depositsCountByIndex(indexByWallet(wallet) - 1);
    }

    /// @notice Get active balance by partner index and currency
    /// @param index The index of the concerned partner
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// return The active balance
    function activeBalanceByIndex(uint256 index, address currencyCt, uint256 currencyId)
    public
    view
    returns (int256)
    {
        // Require partner index is one of registered partner
        require(0 < index && index <= partners.length);

        return _activeBalanceByIndex(index - 1, currencyCt, currencyId);
    }

    /// @notice Get active balance by partner name and currency
    /// @param name The name of the concerned partner
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// return The active balance
    function activeBalanceByName(string name, address currencyCt, uint256 currencyId)
    public
    view
    returns (int256)
    {
        // Implicitly require that partner name is registered
        return _activeBalanceByIndex(indexByName(name) - 1, currencyCt, currencyId);
    }

    /// @notice Get active balance by partner name hash and currency
    /// @param nameHash The hashed name of the concerned partner
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// return The active balance
    function activeBalanceByNameHash(bytes32 nameHash, address currencyCt, uint256 currencyId)
    public
    view
    returns (int256)
    {
        // Implicitly require that partner name hash is registered
        return _activeBalanceByIndex(indexByNameHash(nameHash) - 1, currencyCt, currencyId);
    }

    /// @notice Get active balance by partner wallet and currency
    /// @param wallet The wallet of the concerned partner
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// return The active balance
    function activeBalanceByWallet(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (int256)
    {
        // Implicitly require that partner wallet is registered
        return _activeBalanceByIndex(indexByWallet(wallet) - 1, currencyCt, currencyId);
    }

    /// @notice Get staged balance by partner index and currency
    /// @param index The index of the concerned partner
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// return The staged balance
    function stagedBalanceByIndex(uint256 index, address currencyCt, uint256 currencyId)
    public
    view
    returns (int256)
    {
        // Require partner index is one of registered partner
        require(0 < index && index <= partners.length);

        return _stagedBalanceByIndex(index - 1, currencyCt, currencyId);
    }

    /// @notice Get staged balance by partner name and currency
    /// @param name The name of the concerned partner
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// return The staged balance
    function stagedBalanceByName(string name, address currencyCt, uint256 currencyId)
    public
    view
    returns (int256)
    {
        // Implicitly require that partner name is registered
        return _stagedBalanceByIndex(indexByName(name) - 1, currencyCt, currencyId);
    }

    /// @notice Get staged balance by partner name hash and currency
    /// @param nameHash The hashed name of the concerned partner
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// return The staged balance
    function stagedBalanceByNameHash(bytes32 nameHash, address currencyCt, uint256 currencyId)
    public
    view
    returns (int256)
    {
        // Implicitly require that partner name is registered
        return _stagedBalanceByIndex(indexByNameHash(nameHash) - 1, currencyCt, currencyId);
    }

    /// @notice Get staged balance by partner wallet and currency
    /// @param wallet The wallet of the concerned partner
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// return The staged balance
    function stagedBalanceByWallet(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (int256)
    {
        // Implicitly require that partner wallet is registered
        return _stagedBalanceByIndex(indexByWallet(wallet) - 1, currencyCt, currencyId);
    }

    /// @notice Get the number of partners
    /// @return The number of partners
    function partnersCount()
    public
    view
    returns (uint256)
    {
        return partners.length;
    }

    /// @notice Register a partner by name
    /// @param name The name of the concerned partner
    /// @param fee The partner's fee fraction
    /// @param wallet The partner's wallet
    /// @param partnerCanUpdate Indicator of whether partner can update fee and wallet
    /// @param operatorCanUpdate Indicator of whether operator can update fee and wallet
    function registerByName(string name, uint256 fee, address wallet,
        bool partnerCanUpdate, bool operatorCanUpdate)
    public
    onlyOperator
    {
        // Require not empty name string
        require(bytes(name).length > 0);

        // Hash name
        bytes32 nameHash = hashName(name);

        // Register partner
        _registerPartnerByNameHash(nameHash, fee, wallet, partnerCanUpdate, operatorCanUpdate);

        // Emit event
        emit RegisterPartnerByNameEvent(name, fee, wallet);
    }

    /// @notice Register a partner by name hash
    /// @param nameHash The hashed name of the concerned partner
    /// @param fee The partner's fee fraction
    /// @param wallet The partner's wallet
    /// @param partnerCanUpdate Indicator of whether partner can update fee and wallet
    /// @param operatorCanUpdate Indicator of whether operator can update fee and wallet
    function registerByNameHash(bytes32 nameHash, uint256 fee, address wallet,
        bool partnerCanUpdate, bool operatorCanUpdate)
    public
    onlyOperator
    {
        // Register partner
        _registerPartnerByNameHash(nameHash, fee, wallet, partnerCanUpdate, operatorCanUpdate);

        // Emit event
        emit RegisterPartnerByNameHashEvent(nameHash, fee, wallet);
    }

    /// @notice Gets the 1-based index of partner by its name
    /// @dev Reverts if name does not correspond to registered partner
    /// @return Index of partner by given name
    function indexByNameHash(bytes32 nameHash)
    public
    view
    returns (uint256)
    {
        uint256 index = _indexByNameHash[nameHash];
        require(0 < index);
        return index;
    }

    /// @notice Gets the 1-based index of partner by its name
    /// @dev Reverts if name does not correspond to registered partner
    /// @return Index of partner by given name
    function indexByName(string name)
    public
    view
    returns (uint256)
    {
        return indexByNameHash(hashName(name));
    }

    /// @notice Gets the 1-based index of partner by its wallet
    /// @dev Reverts if wallet does not correspond to registered partner
    /// @return Index of partner by given wallet
    function indexByWallet(address wallet)
    public
    view
    returns (uint256)
    {
        uint256 index = _indexByWallet[wallet];
        require(0 < index);
        return index;
    }

    /// @notice Gauge whether a partner by the given name is registered
    /// @param name The name of the concerned partner
    /// @return true if partner is registered, else false
    function isRegisteredByName(string name)
    public
    view
    returns (bool)
    {
        return (0 < _indexByNameHash[hashName(name)]);
    }

    /// @notice Gauge whether a partner by the given name hash is registered
    /// @param nameHash The hashed name of the concerned partner
    /// @return true if partner is registered, else false
    function isRegisteredByNameHash(bytes32 nameHash)
    public
    view
    returns (bool)
    {
        return (0 < _indexByNameHash[nameHash]);
    }

    /// @notice Gauge whether a partner by the given wallet is registered
    /// @param wallet The wallet of the concerned partner
    /// @return true if partner is registered, else false
    function isRegisteredByWallet(address wallet)
    public
    view
    returns (bool)
    {
        return (0 < _indexByWallet[wallet]);
    }

    /// @notice Get the partner fee fraction by the given partner index
    /// @param index The index of the concerned partner
    /// @return The fee fraction
    function feeByIndex(uint256 index)
    public
    view
    returns (uint256)
    {
        // Require partner index is one of registered partner
        require(0 < index && index <= partners.length);

        return _partnerFeeByIndex(index - 1);
    }

    /// @notice Get the partner fee fraction by the given partner name
    /// @param name The name of the concerned partner
    /// @return The fee fraction
    function feeByName(string name)
    public
    view
    returns (uint256)
    {
        // Get fee, implicitly requiring that partner name is registered
        return _partnerFeeByIndex(indexByName(name) - 1);
    }

    /// @notice Get the partner fee fraction by the given partner name hash
    /// @param nameHash The hashed name of the concerned partner
    /// @return The fee fraction
    function feeByNameHash(bytes32 nameHash)
    public
    view
    returns (uint256)
    {
        // Get fee, implicitly requiring that partner name hash is registered
        return _partnerFeeByIndex(indexByNameHash(nameHash) - 1);
    }

    /// @notice Get the partner fee fraction by the given partner wallet
    /// @param wallet The wallet of the concerned partner
    /// @return The fee fraction
    function feeByWallet(address wallet)
    public
    view
    returns (uint256)
    {
        // Get fee, implicitly requiring that partner wallet is registered
        return _partnerFeeByIndex(indexByWallet(wallet) - 1);
    }

    /// @notice Set the partner fee fraction by the given partner index
    /// @param index The index of the concerned partner
    /// @param newFee The partner's fee fraction
    function setFeeByIndex(uint256 index, uint256 newFee)
    public
    {
        // Require partner index is one of registered partner
        require(0 < index && index <= partners.length);

        // Update fee
        uint256 oldFee = _setPartnerFeeByIndex(index - 1, newFee);

        // Emit event
        emit SetFeeByIndexEvent(index, oldFee, newFee);
    }

    /// @notice Set the partner fee fraction by the given partner name
    /// @param name The name of the concerned partner
    /// @param newFee The partner's fee fraction
    function setFeeByName(string name, uint256 newFee)
    public
    {
        // Update fee, implicitly requiring that partner name is registered
        uint256 oldFee = _setPartnerFeeByIndex(indexByName(name) - 1, newFee);

        // Emit event
        emit SetFeeByNameEvent(name, oldFee, newFee);
    }

    /// @notice Set the partner fee fraction by the given partner name hash
    /// @param nameHash The hashed name of the concerned partner
    /// @param newFee The partner's fee fraction
    function setFeeByNameHash(bytes32 nameHash, uint256 newFee)
    public
    {
        // Update fee, implicitly requiring that partner name hash is registered
        uint256 oldFee = _setPartnerFeeByIndex(indexByNameHash(nameHash) - 1, newFee);

        // Emit event
        emit SetFeeByNameHashEvent(nameHash, oldFee, newFee);
    }

    /// @notice Set the partner fee fraction by the given partner wallet
    /// @param wallet The wallet of the concerned partner
    /// @param newFee The partner's fee fraction
    function setFeeByWallet(address wallet, uint256 newFee)
    public
    {
        // Update fee, implicitly requiring that partner wallet is registered
        uint256 oldFee = _setPartnerFeeByIndex(indexByWallet(wallet) - 1, newFee);

        // Emit event
        emit SetFeeByWalletEvent(wallet, oldFee, newFee);
    }

    /// @notice Get the partner wallet by the given partner index
    /// @param index The index of the concerned partner
    /// @return The wallet
    function walletByIndex(uint256 index)
    public
    view
    returns (address)
    {
        // Require partner index is one of registered partner
        require(0 < index && index <= partners.length);

        return partners[index - 1].wallet;
    }

    /// @notice Get the partner wallet by the given partner name
    /// @param name The name of the concerned partner
    /// @return The wallet
    function walletByName(string name)
    public
    view
    returns (address)
    {
        // Get wallet, implicitly requiring that partner name is registered
        return partners[indexByName(name) - 1].wallet;
    }

    /// @notice Get the partner wallet by the given partner name hash
    /// @param nameHash The hashed name of the concerned partner
    /// @return The wallet
    function walletByNameHash(bytes32 nameHash)
    public
    view
    returns (address)
    {
        // Get wallet, implicitly requiring that partner name hash is registered
        return partners[indexByNameHash(nameHash) - 1].wallet;
    }

    /// @notice Set the partner wallet by the given partner index
    /// @param index The index of the concerned partner
    /// @return newWallet The partner's wallet
    function setWalletByIndex(uint256 index, address newWallet)
    public
    {
        // Require partner index is one of registered partner
        require(0 < index && index <= partners.length);

        // Update wallet
        address oldWallet = _setPartnerWalletByIndex(index - 1, newWallet);

        // Emit event
        emit SetPartnerWalletByIndexEvent(index, oldWallet, newWallet);
    }

    /// @notice Set the partner wallet by the given partner name
    /// @param name The name of the concerned partner
    /// @return newWallet The partner's wallet
    function setWalletByName(string name, address newWallet)
    public
    {
        // Update wallet
        address oldWallet = _setPartnerWalletByIndex(indexByName(name) - 1, newWallet);

        // Emit event
        emit SetPartnerWalletByNameEvent(name, oldWallet, newWallet);
    }

    /// @notice Set the partner wallet by the given partner name hash
    /// @param nameHash The hashed name of the concerned partner
    /// @return newWallet The partner's wallet
    function setWalletByNameHash(bytes32 nameHash, address newWallet)
    public
    {
        // Update wallet
        address oldWallet = _setPartnerWalletByIndex(indexByNameHash(nameHash) - 1, newWallet);

        // Emit event
        emit SetPartnerWalletByNameHashEvent(nameHash, oldWallet, newWallet);
    }

    /// @notice Set the new partner wallet by the given old partner wallet
    /// @param oldWallet The old wallet of the concerned partner
    /// @return newWallet The partner's new wallet
    function setWalletByWallet(address oldWallet, address newWallet)
    public
    {
        // Update wallet
        _setPartnerWalletByIndex(indexByWallet(oldWallet) - 1, newWallet);

        // Emit event
        emit SetPartnerWalletByWalletEvent(oldWallet, newWallet);
    }

    /// @notice Stage the amount for subsequent withdrawal
    /// @param amount The concerned amount to stage
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function stage(int256 amount, address currencyCt, uint256 currencyId)
    public
    {
        // Get index, implicitly requiring that msg.sender is wallet of registered partner
        uint256 index = indexByWallet(msg.sender);

        // Require positive amount
        require(amount.isPositiveInt256());

        // Clamp amount to move
        amount = amount.clampMax(partners[index - 1].active.get(currencyCt, currencyId));

        partners[index - 1].active.sub(amount, currencyCt, currencyId);
        partners[index - 1].staged.add(amount, currencyCt, currencyId);

        partners[index - 1].txHistory.addDeposit(amount, currencyCt, currencyId);

        // Add to full deposit history
        partners[index - 1].fullBalanceHistory.push(
            FullBalanceHistory(
                partners[index - 1].txHistory.depositsCount() - 1,
                partners[index - 1].active.get(currencyCt, currencyId),
                block.number
            )
        );

        // Emit event
        emit StageEvent(msg.sender, amount, currencyCt, currencyId);
    }

    /// @notice Withdraw the given amount from staged balance
    /// @param amount The concerned amount to withdraw
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param standard The standard of the token ("" for default registered, "ERC20", "ERC721")
    function withdraw(int256 amount, address currencyCt, uint256 currencyId, string standard)
    public
    {
        // Get index, implicitly requiring that msg.sender is wallet of registered partner
        uint256 index = indexByWallet(msg.sender);

        // Require positive amount
        require(amount.isPositiveInt256());

        // Clamp amount to move
        amount = amount.clampMax(partners[index - 1].staged.get(currencyCt, currencyId));

        partners[index - 1].staged.sub(amount, currencyCt, currencyId);

        // Execute transfer
        if (address(0) == currencyCt && 0 == currencyId)
            msg.sender.transfer(uint256(amount));

        else {
            TransferController controller = transferController(currencyCt, standard);
            require(
                address(controller).delegatecall(
                    controller.getDispatchSignature(), this, msg.sender, uint256(amount), currencyCt, currencyId
                )
            );
        }

        // Emit event
        emit WithdrawEvent(msg.sender, amount, currencyCt, currencyId);
    }

    //
    // Private functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @dev index is 0-based
    function _receiveEthersTo(uint256 index, int256 amount)
    private
    {
        // Require that index is within bounds
        require(index < partners.length);

        // Add to active
        partners[index].active.add(amount, address(0), 0);
        partners[index].txHistory.addDeposit(amount, address(0), 0);

        // Add to full deposit history
        partners[index].fullBalanceHistory.push(
            FullBalanceHistory(
                partners[index].txHistory.depositsCount() - 1,
                partners[index].active.get(address(0), 0),
                block.number
            )
        );

        // Emit event
        emit ReceiveEvent(msg.sender, amount, address(0), 0);
    }

    /// @dev index is 0-based
    function _receiveTokensTo(uint256 index, int256 amount, address currencyCt,
        uint256 currencyId, string standard)
    private
    {
        // Require that index is within bounds
        require(index < partners.length);

        require(amount.isNonZeroPositiveInt256());

        // Execute transfer
        TransferController controller = transferController(currencyCt, standard);
        require(
            address(controller).delegatecall(
                controller.getReceiveSignature(), msg.sender, this, uint256(amount), currencyCt, currencyId
            )
        );

        // Add to active
        partners[index].active.add(amount, currencyCt, currencyId);
        partners[index].txHistory.addDeposit(amount, currencyCt, currencyId);

        // Add to full deposit history
        partners[index].fullBalanceHistory.push(
            FullBalanceHistory(
                partners[index].txHistory.depositsCount() - 1,
                partners[index].active.get(currencyCt, currencyId),
                block.number
            )
        );

        // Emit event
        emit ReceiveEvent(msg.sender, amount, currencyCt, currencyId);
    }

    /// @dev partnerIndex is 0-based
    function _depositByIndices(uint256 partnerIndex, uint256 depositIndex)
    private
    view
    returns (int256 balance, uint256 blockNumber, address currencyCt, uint256 currencyId)
    {
        require(depositIndex < partners[partnerIndex].fullBalanceHistory.length);

        FullBalanceHistory storage entry = partners[partnerIndex].fullBalanceHistory[depositIndex];
        (,, currencyCt, currencyId) = partners[partnerIndex].txHistory.deposit(entry.listIndex);

        balance = entry.balance;
        blockNumber = entry.blockNumber;
    }

    /// @dev index is 0-based
    function _depositsCountByIndex(uint256 index)
    private
    view
    returns (uint256)
    {
        return partners[index].fullBalanceHistory.length;
    }

    /// @dev index is 0-based
    function _activeBalanceByIndex(uint256 index, address currencyCt, uint256 currencyId)
    private
    view
    returns (int256)
    {
        return partners[index].active.get(currencyCt, currencyId);
    }

    /// @dev index is 0-based
    function _stagedBalanceByIndex(uint256 index, address currencyCt, uint256 currencyId)
    private
    view
    returns (int256)
    {
        return partners[index].staged.get(currencyCt, currencyId);
    }

    function _registerPartnerByNameHash(bytes32 nameHash, uint256 fee, address wallet,
        bool partnerCanUpdate, bool operatorCanUpdate)
    private
    {
        // Require that the name is not previously registered
        require(0 == _indexByNameHash[nameHash]);

        // Require possibility to update
        require(partnerCanUpdate || operatorCanUpdate);

        // Add new partner
        partners.length++;

        // Reference by 1-based index
        uint256 index = partners.length;

        // Update partner map
        partners[index - 1].nameHash = nameHash;
        partners[index - 1].fee = fee;
        partners[index - 1].wallet = wallet;
        partners[index - 1].partnerCanUpdate = partnerCanUpdate;
        partners[index - 1].operatorCanUpdate = operatorCanUpdate;
        partners[index - 1].index = index;

        // Update name hash to index map
        _indexByNameHash[nameHash] = index;

        // Update wallet to index map
        _indexByWallet[wallet] = index;
    }

    /// @dev index is 0-based
    function _setPartnerFeeByIndex(uint256 index, uint256 fee)
    private
    returns (uint256)
    {
        uint256 oldFee = partners[index].fee;

        // If operator tries to change verify that operator has access
        if (isOperator())
            require(partners[index].operatorCanUpdate);

        else {
            // Require that msg.sender is partner
            require(msg.sender == partners[index].wallet);

            // If partner tries to change verify that partner has access
            require(partners[index].partnerCanUpdate);
        }

        // Update stored fee
        partners[index].fee = fee;

        return oldFee;
    }

    // @dev index is 0-based
    function _setPartnerWalletByIndex(uint256 index, address newWallet)
    private
    returns (address)
    {
        address oldWallet = partners[index].wallet;

        // If address has not been set operator is the only allowed to change it
        if (oldWallet == address(0))
            require(isOperator());

        // Else if operator tries to change verify that operator has access
        else if (isOperator())
            require(partners[index].operatorCanUpdate);

        else {
            // Require that msg.sender is partner
            require(msg.sender == oldWallet);

            // If partner tries to change verify that partner has access
            require(partners[index].partnerCanUpdate);

            // Require that new wallet is not zero-address if it can not be changed by operator
            require(partners[index].operatorCanUpdate || newWallet != address(0));
        }

        // Update stored wallet
        partners[index].wallet = newWallet;

        // Update address to tag map
        if (oldWallet != address(0))
            _indexByWallet[oldWallet] = 0;
        if (newWallet != address(0))
            _indexByWallet[newWallet] = index;

        return oldWallet;
    }

    // @dev index is 0-based
    function _partnerFeeByIndex(uint256 index)
    private
    view
    returns (uint256)
    {
        return partners[index].fee;
    }
}
