/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import {Ownable} from "./Ownable.sol";
import {Challenge} from "./Challenge.sol";
import {BalanceTrackable} from "./BalanceTrackable.sol";
import {SafeMathIntLib} from "./SafeMathIntLib.sol";
import {SafeMathUintLib} from "./SafeMathUintLib.sol";
import {NullSettlementDispute} from "./NullSettlementDispute.sol";
import {NahmiiTypesLib} from "./NahmiiTypesLib.sol";
import {SettlementTypesLib} from "./SettlementTypesLib.sol";

/**
 * @title NullSettlementChallenge
 * @notice Where null settlements are started and challenged
 */
contract NullSettlementChallenge is Ownable, Challenge, BalanceTrackable {
    using SafeMathIntLib for int256;
    using SafeMathUintLib for uint256;

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    NullSettlementDispute public nullSettlementDispute;

    uint256 public nonce;

    address[] public challengeWallets;
    mapping(address => bool) challengeByWallets;

    address[] public lockedWallets;
    mapping(address => bool) public lockedByWallet;
    mapping(address => uint) public unlockTimeByWallet;

    SettlementTypesLib.Proposal[] public proposals;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public proposalIndexByWalletCurrency;
    mapping(address => uint256[]) public proposalIndicesByWallet;

    SettlementTypesLib.Disqualification[] public disqualifications;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public disqualificationIndexByWalletCurrency;

    bytes32[] public candidateHashes;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event SetNullSettlementDisputeEvent(NullSettlementDispute oldNullSettlementDispute,
        NullSettlementDispute newNullSettlementDispute);
    event StartChallengeEvent(address wallet, int256 amount, address stageCurrencyCt,
        uint stageCurrencyId);
    event StartChallengeByProxyEvent(address proxy, address wallet, int256 amount,
        address stageCurrencyCt, uint stageCurrencyId);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) public {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Set the settlement dispute contract
    /// @param newNullSettlementDispute The (address of) NullSettlementDispute contract instance
    function setNullSettlementDispute(NullSettlementDispute newNullSettlementDispute)
    public
    onlyDeployer
    notNullAddress(newNullSettlementDispute)
    {
        NullSettlementDispute oldNullSettlementDispute = nullSettlementDispute;
        nullSettlementDispute = newNullSettlementDispute;
        emit SetNullSettlementDisputeEvent(oldNullSettlementDispute, nullSettlementDispute);
    }

    /// @notice Get the number of challenge wallets, i.e. wallets that have started null settlement challenge
    /// @return The number of challenge wallets
    function challengeWalletsCount()
    public
    view
    returns (uint256)
    {
        return challengeWallets.length;
    }

    /// @notice Get the number of locked wallets, i.e. wallets whose null settlement challenge has disqualified
    /// @return The number of locked wallets
    function lockedWalletsCount()
    public
    view
    returns (uint256)
    {
        return lockedWallets.length;
    }

    /// @notice Get the number of proposals
    /// @return The number of proposals
    function proposalsCount()
    public
    view
    returns (uint256)
    {
        return proposals.length;
    }

    /// @notice Get the number of challenges
    /// @return The number of challenges
    function disqualificationsCount()
    public
    view
    returns (uint256)
    {
        return disqualifications.length;
    }

    /// @notice Start settlement challenge
    /// @param amount The concerned amount to stage
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function startChallenge(int256 amount, address currencyCt, uint256 currencyId)
    public
    {
        // Require that wallet is not temporarily disqualified
        require(!isLockedWallet(msg.sender));

        // Start challenge for wallet
        _startChallenge(msg.sender, amount, currencyCt, currencyId, true);

        // Emit event
        emit StartChallengeEvent(msg.sender, amount, currencyCt, currencyId);
    }

    /// @notice Start settlement challenge for the given wallet
    /// @param wallet The address of the concerned wallet
    /// @param amount The concerned amount to stage
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function startChallengeByProxy(address wallet, int256 amount, address currencyCt, uint256 currencyId)
    public
    onlyOperator
    {
        // Start challenge for wallet
        _startChallenge(wallet, amount, currencyCt, currencyId, false);

        // Emit event
        emit StartChallengeByProxyEvent(msg.sender, wallet, amount, currencyCt, currencyId);
    }

    /// @notice Gauge whether the proposal for the given wallet and currency has expired
    /// @param wallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return true if proposal has expired, else false
    function hasProposalExpired(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (bool)
    {
        // 1-based index
        uint256 index = proposalIndexByWalletCurrency[wallet][currencyCt][currencyId];
        return (
        0 == index ||
        0 == proposals[index - 1].nonce ||
        block.timestamp >= proposals[index - 1].expirationTime
        );
    }

    /// @notice Get the challenge nonce of the given wallet
    /// @param wallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The challenge nonce
    function proposalNonce(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (uint256)
    {
        uint256 index = proposalIndexByWalletCurrency[wallet][currencyCt][currencyId];
        require(0 != index);
        return proposals[index - 1].nonce;
    }

    /// @notice Get the settlement proposal block number of the given wallet
    /// @param wallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The settlement proposal block number
    function proposalBlockNumber(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (uint256)
    {
        uint256 index = proposalIndexByWalletCurrency[wallet][currencyCt][currencyId];
        require(0 != index);
        return proposals[index - 1].blockNumber;
    }

    /// @notice Get the settlement proposal end time of the given wallet
    /// @param wallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The settlement proposal end time
    function proposalExpirationTime(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (uint256)
    {
        uint256 index = proposalIndexByWalletCurrency[wallet][currencyCt][currencyId];
        require(0 != index);
        return proposals[index - 1].expirationTime;
    }

    /// @notice Get the challenge status of the given wallet
    /// @param wallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The challenge status
    function proposalStatus(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (SettlementTypesLib.Status)
    {
        uint256 index = proposalIndexByWalletCurrency[wallet][currencyCt][currencyId];
        require(0 != index);
        return proposals[index - 1].status;
    }

    /// @notice Get the settlement proposal stage amount of the given wallet and currency
    /// @param wallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The settlement proposal stage amount
    function proposalStageAmount(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (int256)
    {
        uint256 index = proposalIndexByWalletCurrency[wallet][currencyCt][currencyId];
        require(0 != index);
        return proposals[index - 1].stageAmount;
    }

    /// @notice Get the settlement proposal target balance amount of the given wallet and currency
    /// @param wallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The settlement proposal target balance amount
    function proposalTargetBalanceAmount(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (int256)
    {
        uint256 index = proposalIndexByWalletCurrency[wallet][currencyCt][currencyId];
        require(0 != index);
        return proposals[index - 1].targetBalanceAmount;
    }

    /// @notice Get the balance reward of the given wallet's settlement proposal
    /// @param wallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The balance reward of the settlement proposal
    function proposalBalanceReward(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (bool)
    {
        uint256 index = proposalIndexByWalletCurrency[wallet][currencyCt][currencyId];
        require(0 != index);
        return proposals[index - 1].balanceReward;
    }

    /// @notice Get the disqualification candidate type of the given wallet and currency
    /// @param wallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The candidate type of the settlement disqualification
    function disqualificationCandidateType(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (SettlementTypesLib.CandidateType)
    {
        uint256 index = disqualificationIndexByWalletCurrency[wallet][currencyCt][currencyId];
        require(0 != index);
        return disqualifications[index - 1].candidateType;
    }

    /// @notice Get the disqualification candidate hash of the given wallet and currency
    /// @param wallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The candidate hash of the settlement disqualification
    function disqualificationCandidateHash(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (bytes32)
    {
        uint256 index = disqualificationIndexByWalletCurrency[wallet][currencyCt][currencyId];
        require(0 != index);
        return disqualifications[index - 1].candidateHash;
    }

    /// @notice Get the disqualification challenger of the given wallet and currency
    /// @param wallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @return The challenger of the settlement disqualification
    function disqualificationChallenger(address wallet, address currencyCt, uint256 currencyId)
    public
    view
    returns (address)
    {
        uint256 index = disqualificationIndexByWalletCurrency[wallet][currencyCt][currencyId];
        require(0 != index);
        return disqualifications[index - 1].challenger;
    }

    /// @notice Set settlement proposal end time property of the given wallet
    /// @dev This function can only be called by this contract's dispute instance
    /// @param wallet The address of the concerned wallet
    /// @param expirationTime The end time value
    function setProposalExpirationTime(address wallet, address currencyCt, uint256 currencyId,
        uint256 expirationTime)
    public
    onlyNullSettlementDispute
    {
        uint256 index = proposalIndexByWalletCurrency[wallet][currencyCt][currencyId];
        require(0 != index);
        proposals[index - 1].expirationTime = expirationTime;
    }

    /// @notice Set settlement proposal status property of the given wallet
    /// @dev This function can only be called by this contract's dispute instance
    /// @param wallet The address of the concerned wallet
    /// @param status The status value
    function setProposalStatus(address wallet, address currencyCt, uint256 currencyId,
        SettlementTypesLib.Status status)
    public
    onlyNullSettlementDispute
    {
        uint256 index = proposalIndexByWalletCurrency[wallet][currencyCt][currencyId];
        require(0 != index);
        proposals[index - 1].status = status;
    }

    /// @notice Challenge the settlement by providing order candidate
    /// @param order The order candidate that challenges the null
    function challengeByOrder(NahmiiTypesLib.Order order)
    public
    onlyOperationalModeNormal
    {
        nullSettlementDispute.challengeByOrder(order, msg.sender);
    }

    /// @notice Challenge the settlement by providing trade candidate
    /// @param wallet The wallet whose settlement is being challenged
    /// @param trade The trade candidate that challenges the null
    function challengeByTrade(address wallet, NahmiiTypesLib.Trade trade)
    public
    onlyOperationalModeNormal
    {
        nullSettlementDispute.challengeByTrade(wallet, trade, msg.sender);
    }

    /// @notice Challenge the settlement by providing payment candidate
    /// @param wallet The wallet whose settlement is being challenged
    /// @param payment The payment candidate that challenges the null
    function challengeByPayment(address wallet, NahmiiTypesLib.Payment payment)
    public
    onlyOperationalModeNormal
    {
        nullSettlementDispute.challengeByPayment(wallet, payment, msg.sender);
    }

    /// @notice Get the count of challenge candidate hashes
    /// @return The count of challenge candidate order hashes
    function candidateHashesCount()
    public
    view
    returns (uint256)
    {
        return candidateHashes.length;
    }

    /// @notice Disqualify the given wallet
    /// @dev This function can only be called by this contract's dispute instance
    /// @param wallet The address of the concerned wallet
    function lockWallet(address wallet)
    public
    onlyNullSettlementDispute
    {
        if (0 == unlockTimeByWallet[wallet]) {
            lockedWallets.push(wallet);
            lockedByWallet[wallet] = true;
        }

        unlockTimeByWallet[wallet] = block.timestamp.add(configuration.walletLockTimeout());
    }

    /// @notice Gauge whether the wallet is (temporarily) locked
    /// @param wallet The address of the concerned wallet
    /// @return true if wallet is locked, else false
    function isLockedWallet(address wallet)
    public
    view
    returns (bool)
    {
        return block.timestamp < unlockTimeByWallet[wallet];
    }

    /// @notice Add a disqualification instance
    /// @param wallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    /// @param candidateHash The candidate hash
    /// @param candidateType The candidate type
    /// @param challenger The concerned challenger
    function addDisqualification(address wallet, address currencyCt, uint256 currencyId, bytes32 candidateHash,
        SettlementTypesLib.CandidateType candidateType, address challenger)
    public
    onlyNullSettlementDispute
    {
        // Get the proposal index
        uint256 index = proposalIndexByWalletCurrency[wallet][currencyCt][currencyId];
        require(0 != index);

        // Create disqualification
        disqualifications.length++;

        // Populate disqualification
        disqualifications[disqualifications.length - 1].wallet = wallet;
        disqualifications[disqualifications.length - 1].nonce = proposals[index - 1].nonce;
        disqualifications[disqualifications.length - 1].currencyCt = currencyCt;
        disqualifications[disqualifications.length - 1].currencyId = currencyId;
        disqualifications[disqualifications.length - 1].candidateHash = candidateHash;
        disqualifications[disqualifications.length - 1].candidateType = candidateType;
        disqualifications[disqualifications.length - 1].challenger = challenger;

        // Store disqualification index
        disqualificationIndexByWalletCurrency[wallet][currencyCt][currencyId] = disqualifications.length;

        // Store candidate hash
        candidateHashes.push(candidateHash);
    }

    //
    // Private functions
    // -----------------------------------------------------------------------------------------------------------------
    function _startChallenge(address wallet, int256 stageAmount, address currencyCt, uint256 currencyId,
        bool balanceReward)
    private
    {
        // Require that current block number is beyond the earliest settlement challenge block number
        require(block.number >= configuration.earliestSettlementBlockNumber());

        // Require that stage amount is positive
        require(stageAmount.isPositiveInt256());

        // Require that wallet has no overlap with active proposal
        require(
            hasProposalExpired(
                wallet, currencyCt, currencyId
            )
        );

        // Get the last logged active balance amount and block number
        (int256 activeBalanceAmount, uint256 activeBalanceBlockNumber) =
        _activeBalanceLogEntry(wallet, currencyCt, currencyId);

        // Require that balance amount is not less than stage amount
        require(activeBalanceAmount >= stageAmount);

        // Create proposal
        proposals.length++;

        // Populate proposal
        proposals[proposals.length - 1].wallet = wallet;
        proposals[proposals.length - 1].nonce = ++nonce;
        proposals[proposals.length - 1].blockNumber = activeBalanceBlockNumber;
        proposals[proposals.length - 1].expirationTime = block.timestamp.add(configuration.settlementChallengeTimeout());
        proposals[proposals.length - 1].status = SettlementTypesLib.Status.Qualified;
        proposals[proposals.length - 1].currencyCt = currencyCt;
        proposals[proposals.length - 1].currencyId = currencyId;
        proposals[proposals.length - 1].stageAmount = stageAmount;
        proposals[proposals.length - 1].targetBalanceAmount = activeBalanceAmount.sub(stageAmount);
        proposals[proposals.length - 1].balanceReward = balanceReward;

        // Store proposal index
        proposalIndexByWalletCurrency[wallet][currencyCt][currencyId] = proposals.length;
        proposalIndicesByWallet[wallet].push(proposals.length);

        // Add wallet to store of challenge wallets
        if (!challengeByWallets[wallet]) {
            challengeByWallets[wallet] = true;
            challengeWallets.push(wallet);
        }
    }

    function _activeBalanceLogEntry(address wallet, address currencyCt, uint256 currencyId)
    private
    view
    returns (int256 amount, uint256 blockNumber)
    {
        // Get last log record of deposited and settled balances
        (int256 depositedAmount, uint256 depositedBlockNumber) = balanceTracker.lastFungibleRecord(
            wallet, balanceTracker.depositedBalanceType(), currencyCt, currencyId
        );
        (int256 settledAmount, uint256 settledBlockNumber) = balanceTracker.lastFungibleRecord(
            wallet, balanceTracker.settledBalanceType(), currencyCt, currencyId
        );

        // Set amount as the sum of deposited and settled
        amount = depositedAmount.add(settledAmount);

        // Set block number as the latest of deposited and settled
        blockNumber = depositedBlockNumber > settledBlockNumber ? depositedBlockNumber : settledBlockNumber;
    }

    //
    // Modifiers
    // -----------------------------------------------------------------------------------------------------------------
    modifier onlyNullSettlementDispute() {
        require(msg.sender == address(nullSettlementDispute));
        _;
    }
}
