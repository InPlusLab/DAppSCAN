// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { IInsuranceFund } from '../IInsuranceFund.sol';
import { IOracle } from '../IOracle.sol';
import { IVQuote } from '../IVQuote.sol';
import { IVToken } from '../IVToken.sol';

import { IClearingHouseStructures } from './IClearingHouseStructures.sol';

interface IClearingHouseSystemActions is IClearingHouseStructures {
    /// @notice initializes clearing house contract
    /// @param rageTradeFactoryAddress rage trade factory address
    /// @param defaultCollateralToken address of default collateral token
    /// @param defaultCollateralTokenOracle address of default collateral token oracle
    /// @param insuranceFund address of insurance fund
    /// @param vQuote address of vQuote
    function initialize(
        address rageTradeFactoryAddress,
        IERC20 defaultCollateralToken,
        IOracle defaultCollateralTokenOracle,
        IInsuranceFund insuranceFund,
        IVQuote vQuote
    ) external;

    function registerPool(Pool calldata poolInfo) external;
}
