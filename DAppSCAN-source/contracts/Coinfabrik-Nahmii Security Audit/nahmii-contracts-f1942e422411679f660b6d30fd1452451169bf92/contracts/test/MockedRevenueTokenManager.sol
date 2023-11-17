/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import {MockedRevenueToken} from "./MockedRevenueToken.sol";

/**
 * @title MockedRevenueTokenManager
 * @notice Mocked implementation of RevenueTokenManager
 */
contract MockedRevenueTokenManager {
    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    MockedRevenueToken public token;
    uint256 public _releasedAmountBlocksIn;

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor() public
    {
        token = new MockedRevenueToken();
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    function _reset()
    public
    {
        _releasedAmountBlocksIn = 0;
    }

    function releasedAmountBlocksIn(uint256, uint256)
    public
    view
    returns (uint256)
    {
        return _releasedAmountBlocksIn;
    }

    function _setReleasedAmountBlocksIn(uint256 _rabIn)
    public
    {
        _releasedAmountBlocksIn = _rabIn;
    }
}
