/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

/**
 * @title MockedRevenueToken
 * @notice Mocked implementation of RevenueToken
 */
contract MockedRevenueToken {
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    uint256 public _balanceBlocksIn;

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    function _reset()
    public
    {
        _balanceBlocksIn = 0;
    }

    function balanceBlocksIn(address, uint256, uint256)
    public
    view
    returns (uint256)
    {
        return _balanceBlocksIn;
    }

    function _setBalanceBlocksIn(uint256 _bbIn)
    public
    {
        _balanceBlocksIn = _bbIn;
    }
}
