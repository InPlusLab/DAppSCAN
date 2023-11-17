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
import {Configurable} from "./Configurable.sol";
import {ClientFundable} from "./ClientFundable.sol";
import {CommunityVotable} from "./CommunityVotable.sol";
import {RevenueFund} from "./RevenueFund.sol";
import {NullSettlementChallenge} from "./NullSettlementChallenge.sol";
import {Beneficiary} from "./Beneficiary.sol";
import {SafeMathIntLib} from "./SafeMathIntLib.sol";
import {SafeMathUintLib} from "./SafeMathUintLib.sol";
import {SettlementTypesLib} from "./SettlementTypesLib.sol";

/**
 * @title NullSettlement
 * @notice Where null settlement are finalized
 */
contract NullSettlement is Ownable, Configurable, ClientFundable, CommunityVotable {
    using SafeMathIntLib for int256;
    using SafeMathUintLib for uint256;

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    NullSettlementChallenge public nullSettlementChallenge;

    uint256 public maxNullNonce;

    mapping(address => mapping(address => mapping(uint256 => uint256))) public walletCurrencyMaxNullNonce;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event SetNullSettlementChallengeEvent(NullSettlementChallenge oldNullSettlementChallenge,
        NullSettlementChallenge newNullSettlementChallenge);
    event SettleNullEvent(address wallet, address currencyCt, uint256 currencyId);
    event SettleNullByProxyEvent(address proxy, address wallet, address currencyCt,
        uint256 currencyId);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) public {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Set the null settlement challenge contract
    /// @param newNullSettlementChallenge The (address of) NullSettlementChallenge contract instance
    function setNullSettlementChallenge(NullSettlementChallenge newNullSettlementChallenge)
    public
    onlyDeployer
    notNullAddress(newNullSettlementChallenge)
    {
        NullSettlementChallenge oldNullSettlementChallenge = nullSettlementChallenge;
        nullSettlementChallenge = newNullSettlementChallenge;
        emit SetNullSettlementChallengeEvent(oldNullSettlementChallenge, nullSettlementChallenge);
    }

    /// @notice Update the max null settlement nonce property from CommunityVote contract
    function updateMaxNullNonce()
    public
    {
        uint256 _maxNullNonce = communityVote.getMaxNullNonce();
        if (_maxNullNonce > 0)
            maxNullNonce = _maxNullNonce;
    }

    /// @notice Settle null
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function settleNull(address currencyCt, uint256 currencyId)
    public
    {
        // Settle null
        _settleNull(msg.sender, currencyCt, currencyId);

        // Emit event
        emit SettleNullEvent(msg.sender, currencyCt, currencyId);
    }

    /// @notice Settle null by proxy
    /// @param wallet The address of the concerned wallet
    /// @param currencyCt The address of the concerned currency contract (address(0) == ETH)
    /// @param currencyId The ID of the concerned currency (0 for ETH and ERC20)
    function settleNullByProxy(address wallet, address currencyCt, uint256 currencyId)
    public
    onlyOperator
    {
        // Settle null of wallet
        _settleNull(wallet, currencyCt, currencyId);

        // Emit event
        emit SettleNullByProxyEvent(msg.sender, wallet, currencyCt, currencyId);
    }

    //
    // Private functions
    // -----------------------------------------------------------------------------------------------------------------
    function _settleNull(address wallet, address currencyCt, uint256 currencyId)
    private
    {
        // Require that driip settlement challenge qualified
        require(SettlementTypesLib.Status.Qualified == nullSettlementChallenge.proposalStatus(
            wallet, currencyCt, currencyId
        ));

        uint256 nonce = nullSettlementChallenge.proposalNonce(wallet, currencyCt, currencyId);

        // Require that operational mode is normal and data is available, or that nonce is
        // smaller than max null nonce
        require((configuration.isOperationalModeNormal() && communityVote.isDataAvailable())
            || (nonce < maxNullNonce));

        // If wallet has previously settled balance of the concerned currency with higher
        // null settlement nonce, then don't settle again
        require(nonce > walletCurrencyMaxNullNonce[wallet][currencyCt][currencyId]);

        // Update settled nonce of wallet and currency
        walletCurrencyMaxNullNonce[wallet][currencyCt][currencyId] = nonce;

        // Get proposal's stage amount
        int256 stageAmount = nullSettlementChallenge.proposalStageAmount(
            wallet, currencyCt, currencyId
        );

        // Stage the proposed amount
        clientFund.stage(wallet, stageAmount, currencyCt, currencyId, "");

        // If payment nonce is beyond max null settlement nonce then update max null nonce
        if (nonce > maxNullNonce)
            maxNullNonce = nonce;
    }
}