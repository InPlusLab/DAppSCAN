/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {Configurable} from "./Configurable.sol";

/**
 * @title Challenge
 * @notice A configurable with extra for challenges
 */
contract Challenge is Configurable {
    //
    // Modifiers
    // -----------------------------------------------------------------------------------------------------------------
    modifier onlyOperationalModeNormal() {
        require(configuration.isOperationalModeNormal());
        _;
    }
}
