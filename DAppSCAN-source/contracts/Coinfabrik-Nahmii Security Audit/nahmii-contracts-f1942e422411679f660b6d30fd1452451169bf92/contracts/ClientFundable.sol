/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {Ownable} from "./Ownable.sol";
import {ClientFund} from "./ClientFund.sol";

/**
 * @title ClientFundable
 * @notice An ownable that has a client fund property
 */
contract ClientFundable is Ownable {
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    ClientFund public clientFund;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event SetClientFundEvent(ClientFund oldClientFund, ClientFund newClientFund);

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Set the client fund contract
    /// @param newClientFund The (address of) ClientFund contract instance
    function setClientFund(ClientFund newClientFund) public
    onlyDeployer
    notNullAddress(newClientFund)
    notSameAddresses(newClientFund, clientFund)
    {
        // Update field
        ClientFund oldClientFund = clientFund;
        clientFund = newClientFund;

        // Emit event
        emit SetClientFundEvent(oldClientFund, newClientFund);
    }

    //
    // Modifiers
    // -----------------------------------------------------------------------------------------------------------------
    modifier clientFundInitialized() {
        require(clientFund != address(0));
        _;
    }
}
