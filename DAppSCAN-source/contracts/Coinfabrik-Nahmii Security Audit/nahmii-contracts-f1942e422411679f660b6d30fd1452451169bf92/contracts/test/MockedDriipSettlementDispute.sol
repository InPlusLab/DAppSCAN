/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import {NahmiiTypesLib} from "../NahmiiTypesLib.sol";

/**
 * @title MockedDriipSettlementDispute
 * @notice Mocked implementation of driip settlement dispute contract
 */
contract MockedDriipSettlementDispute {
    uint256 public _challengeByOrderCount;
    uint256 public _unchallengeOrderCandidateByTradeCount;
    uint256 public _challengeByTradeCount;
    uint256 public _challengeByPaymentCount;

    function _reset()
    public
    {
        _challengeByOrderCount = 0;
        _unchallengeOrderCandidateByTradeCount = 0;
        _challengeByTradeCount = 0;
        _challengeByPaymentCount = 0;
    }

    function challengeByOrder(NahmiiTypesLib.Order, address)
    public
    {
        _challengeByOrderCount++;
    }

    function unchallengeOrderCandidateByTrade(NahmiiTypesLib.Order, NahmiiTypesLib.Trade,
        address)
    public
    {
        _unchallengeOrderCandidateByTradeCount++;
    }

    function challengeByTrade(address, NahmiiTypesLib.Trade, address)
    public
    {
        _challengeByTradeCount++;
    }

    function challengeByPayment(address, NahmiiTypesLib.Payment, address)
    public
    {
        _challengeByPaymentCount++;
    }
}