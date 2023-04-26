// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;
pragma experimental ABIEncoderV2;

import {SafeMath} from "../../../dependencies/openzeppelin/math/SafeMath.sol";
import {IERC20} from "../../../dependencies/openzeppelin/token/ERC20/IERC20.sol";

import {InstrumentReserveLogic} from './InstrumentReserveLogic.sol';
import {InstrumentConfiguration} from '../configuration/InstrumentConfiguration.sol';
import {UserConfiguration} from '../configuration/UserConfiguration.sol';
import {DataTypes} from '../types/DataTypes.sol';

import {WadRayMath} from '../math/WadRayMath.sol';
import {PercentageMath} from '../math/PercentageMath.sol';

import {IPriceOracleGetter} from "../../../../interfaces/IPriceOracleGetter.sol";

/**
 * @title GenericLogic library
 * @author Aave
 * @title Implements protocol-level logic to calculate and validate the state of a user
 */
library GenericLogic {

    using InstrumentReserveLogic for DataTypes.InstrumentData;
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using InstrumentConfiguration for DataTypes.InstrumentConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1 ether;

    struct balanceDecreaseAllowedLocalVars {
        uint256 decimals;
        uint256 liquidationThreshold;
        uint256 totalCollateralInUSD;
        uint256 totalDebtInUSD;
        uint256 avgLiquidationThreshold;
        uint256 amountToDecreaseInUSD;
        uint256 collateralBalanceAfterDecrease;
        uint256 liquidationThresholdAfterDecrease;
        uint256 healthFactorAfterDecrease;
        bool instrumentUsageAsCollateralEnabled;
    }

    /**
    * @dev Checks if a specific balance decrease is allowed
    * (i.e. doesn't bring the user borrow position health factor under HEALTH_FACTOR_LIQUIDATION_THRESHOLD)
    * @param asset The address of the underlying asset
    * @param user The address of the user
    * @param amount The amount to decrease
    * @param instrumentsData The data of all the instruments
    * @param userConfig The user configuration
    * @param instruments The list of all the active instruments
    * @param oracle The address of the oracle contract
    * @return true if the decrease of the balance is allowed
    **/
    function balanceDecreaseAllowed( address asset, address user, uint256 amount, mapping(address => DataTypes.InstrumentData) storage instrumentsData, DataTypes.UserConfigurationMap calldata userConfig, mapping(uint256 => address) storage instruments,  uint256 instrumentsCount, address oracle) external view returns (bool) {
        if (!userConfig.isBorrowingAny() || !userConfig.isUsingAsCollateral(instrumentsData[asset].id)) {
            return true;
        }
        
        balanceDecreaseAllowedLocalVars memory vars;

        (, vars.liquidationThreshold, , vars.decimals, ) = instrumentsData[asset].configuration.getParams();

        if (vars.liquidationThreshold == 0) {
            return true; 
        }

        (vars.totalCollateralInUSD, vars.totalDebtInUSD, , vars.avgLiquidationThreshold, ) = calculateUserAccountData(user, instrumentsData, userConfig, instruments, instrumentsCount, oracle);

        if (vars.totalDebtInUSD == 0) {
            return true;
        }

        vars.amountToDecreaseInUSD = IPriceOracleGetter(oracle).getAssetPrice(asset).mul(amount).div(  10**vars.decimals);
        vars.collateralBalanceAfterDecrease = vars.totalCollateralInUSD.sub(vars.amountToDecreaseInUSD);

        //if there is a borrow, there can't be 0 collateral
        if (vars.collateralBalanceAfterDecrease == 0) {
            return false;
        }

        vars.liquidationThresholdAfterDecrease = vars.totalCollateralInUSD.mul(vars.avgLiquidationThreshold).sub(vars.amountToDecreaseInUSD.mul(vars.liquidationThreshold)).div(vars.collateralBalanceAfterDecrease);
        uint256 healthFactorAfterDecrease = calculateHealthFactorFromBalances( vars.collateralBalanceAfterDecrease, vars.totalDebtInUSD, vars.liquidationThresholdAfterDecrease );

        return healthFactorAfterDecrease >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD;
    }

    struct CalculateUserAccountDataVars {
        uint256 instrumentUnitPrice;
        uint256 tokenUnit;
        uint256 compoundedLiquidityBalance;
        uint256 compoundedBorrowBalance;
        uint256 decimals;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 i;
        uint256 healthFactor;
        uint256 totalCollateralInUSD;
        uint256 totalDebtInUSD;
        uint256 avgLtv;
        uint256 avgLiquidationThreshold;
        uint256 instrumentsLength;
        bool healthFactorBelowThreshold;
        address currentInstrumentAddress;
        bool usageAsCollateralEnabled;
        bool userUsesInstrumentAsCollateral;
    }

    /**
    * @dev Calculates the user data across the instruments.
    * this includes the total liquidity/collateral/borrow balances in USD, the average Loan To Value, the average Liquidation Ratio, and the Health factor.
    * @param user The address of the user
    * @param instrumentsData Data of all the instruments
    * @param userConfig The configuration of the user
    * @param instruments The list of the available instruments
    * @param oracle The price oracle address
    * @return The total collateral and total debt of the user in USD, the avg ltv, liquidation threshold and the HF
    **/
    function calculateUserAccountData( address user, mapping(address => DataTypes.InstrumentData) storage instrumentsData, DataTypes.UserConfigurationMap memory userConfig, mapping(uint256 => address) storage instruments, uint256 instrumentsCount, address oracle ) internal view returns ( uint256, uint256, uint256, uint256, uint256) {
        CalculateUserAccountDataVars memory vars;

        if (userConfig.isEmpty()) {
            return (0, 0, 0, 0, uint256(-1));
        }

        for (vars.i = 0; vars.i < instrumentsCount; vars.i++) {
            if (!userConfig.isUsingAsCollateralOrBorrowing(vars.i)) {
                continue;
            }

            vars.currentInstrumentAddress = instruments[vars.i];
            DataTypes.InstrumentData storage currentInstrument = instrumentsData[vars.currentInstrumentAddress];

            (vars.ltv, vars.liquidationThreshold, , vars.decimals, ) = currentInstrument.configuration.getParams();
            vars.tokenUnit = 10**vars.decimals;
            vars.instrumentUnitPrice = IPriceOracleGetter(oracle).getAssetPrice(vars.currentInstrumentAddress);

            if (vars.liquidationThreshold != 0 && userConfig.isUsingAsCollateral(vars.i)) {
                vars.compoundedLiquidityBalance = IERC20(currentInstrument.iTokenAddress).balanceOf(user);
                uint256 liquidityBalanceUSD = vars.instrumentUnitPrice.mul(vars.compoundedLiquidityBalance).div(vars.tokenUnit);
                vars.totalCollateralInUSD = vars.totalCollateralInUSD.add(liquidityBalanceUSD);

                vars.avgLtv = vars.avgLtv.add(liquidityBalanceUSD.mul(vars.ltv));
                vars.avgLiquidationThreshold = vars.avgLiquidationThreshold.add(  liquidityBalanceUSD.mul(vars.liquidationThreshold)  );
            }

            if (userConfig.isBorrowing(vars.i)) {
                vars.compoundedBorrowBalance = IERC20(currentInstrument.stableDebtTokenAddress).balanceOf( user );
                vars.compoundedBorrowBalance = vars.compoundedBorrowBalance.add( IERC20(currentInstrument.variableDebtTokenAddress).balanceOf(user) );
                vars.totalDebtInUSD = vars.totalDebtInUSD.add(  vars.instrumentUnitPrice.mul(vars.compoundedBorrowBalance).div(vars.tokenUnit) );
            }
        }

        vars.avgLtv = vars.totalCollateralInUSD > 0 ? vars.avgLtv.div(vars.totalCollateralInUSD) : 0;
        vars.avgLiquidationThreshold = vars.totalCollateralInUSD > 0 ? vars.avgLiquidationThreshold.div(vars.totalCollateralInUSD) : 0;

        vars.healthFactor = calculateHealthFactorFromBalances( vars.totalCollateralInUSD, vars.totalDebtInUSD, vars.avgLiquidationThreshold);
        return ( vars.totalCollateralInUSD, vars.totalDebtInUSD, vars.avgLtv, vars.avgLiquidationThreshold, vars.healthFactor );
    }

    /**
    * @dev Calculates the health factor from the corresponding balances
    * @param totalCollateralInUSD The total collateral in USD
    * @param totalDebtInUSD The total debt in USD
    * @param liquidationThreshold The avg liquidation threshold
    * @return The health factor calculated from the balances provided
    **/
    function calculateHealthFactorFromBalances( uint256 totalCollateralInUSD, uint256 totalDebtInUSD,  uint256 liquidationThreshold) internal pure returns (uint256) {
        if (totalDebtInUSD == 0)
            return uint256(-1);
        return (totalCollateralInUSD.percentMul(liquidationThreshold)).wadDiv(totalDebtInUSD);
    }

    /**
    * @dev Calculates the equivalent amount in USD that an user can borrow, depending on the available collateral and the average Loan To Value
    * @param totalCollateralInUSD The total collateral in USD
    * @param totalDebtInUSD The total borrow balance
    * @param ltv The average loan to value
    * @return the amount available to borrow in USD for the user
    **/
    function calculateAvailableBorrowsUSD(uint256 totalCollateralInUSD,uint256 totalDebtInUSD,uint256 ltv) internal pure returns (uint256) {
        uint256 availableBorrowsUSD = totalCollateralInUSD.percentMul(ltv);

        if (availableBorrowsUSD < totalDebtInUSD) {
            return 0;
        }

        availableBorrowsUSD = availableBorrowsUSD.sub(totalDebtInUSD);
        return availableBorrowsUSD;
    }
}