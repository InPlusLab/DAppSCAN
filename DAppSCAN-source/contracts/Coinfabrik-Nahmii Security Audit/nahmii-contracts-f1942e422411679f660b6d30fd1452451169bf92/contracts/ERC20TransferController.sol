/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;

import {TransferController} from "./TransferController.sol";
import {IERC20} from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

/**
 * @title ERC20TransferController
 * @notice Handles transfers of ERC20 tokens
 */
contract ERC20TransferController is TransferController {
    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    function isFungible()
    public
    view
    returns (bool)
    {
        return true;
    }

    /// @notice MUST be called with DELEGATECALL
    function receive(address from, address to, uint256 amount, address currencyCt, uint256 currencyId)
    public
    {
        require(msg.sender != address(0));
        require(amount > 0);
        require(currencyId == 0);

        require(IERC20(currencyCt).transferFrom(from, to, amount));

        // Emit event
        emit CurrencyTransferred(from, to, amount, currencyCt, currencyId);
    }

    /// @notice MUST be called with DELEGATECALL
    function approve(address to, uint256 amount, address currencyCt, uint256 currencyId)
    public
    {
        require(amount > 0);
        require(currencyId == 0);

        require(IERC20(currencyCt).approve(to, amount));
    }

    /// @notice MUST be called with DELEGATECALL
    function dispatch(address from, address to, uint256 amount, address currencyCt, uint256 currencyId)
    public
    {
        require(amount > 0);
        require(currencyId == 0);

        require(IERC20(currencyCt).approve(from, amount));
        require(IERC20(currencyCt).transferFrom(from, to, amount));

        // Emit event
        emit CurrencyTransferred(from, to, amount, currencyCt, currencyId);
    }
}

