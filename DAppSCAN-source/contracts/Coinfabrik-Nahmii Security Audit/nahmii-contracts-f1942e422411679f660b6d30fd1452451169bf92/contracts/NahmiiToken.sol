/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {RevenueToken} from "./RevenueToken.sol";

/**
 * @title NahmiiToken
 * @dev The ERC20 token for receiving revenue from nahmii and partake in its distributed governance
 */
contract NahmiiToken is RevenueToken {

    string public name = "Nahmii";

    string public symbol = "NII";

    uint8 public constant decimals = 15;

    event SetName(string name);

    event SetSymbol(string symbol);

    /**
     * @dev Set the name of the token
     * @param _name The new token name
     */
    function setName(string _name)
    public
    onlyMinter
    {
        name = _name;
        emit SetName(name);
    }

    /**
     * @dev Set the symbol of the token
     * @param _symbol The new token symbol
     */
    function setSymbol(string _symbol)
    public
    onlyMinter
    {
        symbol = _symbol;
        emit SetSymbol(_symbol);
    }
}