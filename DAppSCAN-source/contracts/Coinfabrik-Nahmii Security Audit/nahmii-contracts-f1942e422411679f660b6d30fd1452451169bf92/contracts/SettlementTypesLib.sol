/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import {NahmiiTypesLib} from "./NahmiiTypesLib.sol";

/**
 * @title     SettlementTypesLib
 * @dev       Types for settlements
 */
library SettlementTypesLib {
    //
    // Structures
    // -----------------------------------------------------------------------------------------------------------------
    enum Status {Qualified, Disqualified}
    enum CandidateType {None, Order, Trade, Payment}
    enum SettlementRole {Origin, Target}

    struct Proposal {
        address wallet;
        uint256 nonce;
        uint256 blockNumber;

        uint256 expirationTime;

        // Status
        Status status;

        // Currency
        address currencyCt;
        uint256 currencyId;

        // Stage info
        int256 stageAmount;

        // Balances after amounts have been staged
        int256 targetBalanceAmount;

        // Driip info
        bytes32 driipHash;
        NahmiiTypesLib.DriipType driipType;

        // True if reward is from wallet balance
        bool balanceReward;
    }

    struct Disqualification {
        address wallet;
        uint256 nonce;

        // Currency
        address currencyCt;
        uint256 currencyId;

        // Candidate info
        bytes32 candidateHash;
        CandidateType candidateType;

        // Address of wallet that successfully challenged
        address challenger;
    }

    struct SettlementParty {
        uint256 nonce;
        address wallet;
        bool done;
    }

    struct Settlement {
        uint256 nonce;
        NahmiiTypesLib.DriipType driipType;
        SettlementParty origin;
        SettlementParty target;
    }
}