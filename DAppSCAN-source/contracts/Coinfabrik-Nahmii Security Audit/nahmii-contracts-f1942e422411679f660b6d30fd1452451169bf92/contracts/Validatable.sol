/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {Ownable} from "./Ownable.sol";
import {Validator} from "./Validator.sol";
import {NahmiiTypesLib} from "./NahmiiTypesLib.sol";

/**
 * @title Validatable
 * @notice An ownable that has a validator property
 */
contract Validatable is Ownable {
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    Validator public validator;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event SetValidatorEvent(Validator oldValidator, Validator newValidator);

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Set the validator contract
    /// @param newValidator The (address of) Validator contract instance
    function setValidator(Validator newValidator)
    public
    onlyDeployer
    notNullAddress(newValidator)
    notSameAddresses(newValidator, validator)
    {
        //set new validator
        Validator oldValidator = validator;
        validator = newValidator;

        // Emit event
        emit SetValidatorEvent(oldValidator, newValidator);
    }

    //
    // Modifiers
    // -----------------------------------------------------------------------------------------------------------------
    modifier validatorInitialized() {
        require(validator != address(0));
        _;
    }

    modifier onlySealedOrder(NahmiiTypesLib.Order order) {
        require(validator.isGenuineOrderSeals(order));
        _;
    }

    modifier onlyOperatorSealedOrder(NahmiiTypesLib.Order order) {
        require(validator.isGenuineOrderOperatorSeal(order));
        _;
    }

    modifier onlySealedTrade(NahmiiTypesLib.Trade trade) {
        require(validator.isGenuineTradeSeal(trade));
        _;
    }

    modifier onlyOperatorSealedPayment(NahmiiTypesLib.Payment payment) {
        require(validator.isGenuinePaymentOperatorSeal(payment));
        _;
    }

    modifier onlySealedPayment(NahmiiTypesLib.Payment payment) {
        require(validator.isGenuinePaymentSeals(payment));
        _;
    }

    modifier onlyTradeParty(NahmiiTypesLib.Trade trade, address wallet) {
        require(validator.isTradeParty(trade, wallet));
        _;
    }

    modifier onlyPaymentParty(NahmiiTypesLib.Payment payment, address wallet) {
        require(validator.isPaymentParty(payment, wallet));
        _;
    }
}
