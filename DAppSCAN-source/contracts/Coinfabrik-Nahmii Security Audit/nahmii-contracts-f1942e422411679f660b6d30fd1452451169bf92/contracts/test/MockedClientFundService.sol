/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import {Ownable} from "../Ownable.sol";
import {ClientFundable} from "../ClientFundable.sol";
import {Beneficiary} from "../Beneficiary.sol";

/**
 * @title MockedClientFundService
 * @notice Mocked implementation of service contract that interacts with ClientFund
 */
contract MockedClientFundService is Ownable, ClientFundable {
    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) public {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    function updateSettledBalance(address wallet, int256 amount, address currencyCt, uint256 currencyId,
        string standard, uint256 blockNumber)
    public
    {
        clientFund.updateSettledBalance(wallet, amount, currencyCt, currencyId, standard, blockNumber);
    }

    function stage(address wallet, int256 amount, address currencyCt, uint256 currencyId, string standard)
    public
    {
        clientFund.stage(wallet, amount, currencyCt, currencyId, standard);
    }

    function stageToBeneficiary(address wallet, Beneficiary beneficiary, int256 amount,
        address currencyCt, uint256 currencyId, string standard)
    public
    {
        clientFund.stageToBeneficiary(wallet, beneficiary, amount, currencyCt, currencyId, standard);
    }

    function transferToBeneficiary(address wallet, Beneficiary beneficiary, int256 amount,
        address currencyCt, uint256 currencyId, string standard)
    public
    {
        clientFund.transferToBeneficiary(wallet, beneficiary, amount, currencyCt, currencyId, standard);
    }
}