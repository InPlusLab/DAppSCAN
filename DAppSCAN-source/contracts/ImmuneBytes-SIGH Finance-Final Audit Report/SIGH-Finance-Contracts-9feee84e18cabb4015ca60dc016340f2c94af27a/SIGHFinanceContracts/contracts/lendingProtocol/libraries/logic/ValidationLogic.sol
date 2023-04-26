// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;
pragma experimental ABIEncoderV2;

import  {SafeMath} from "../../../dependencies/openzeppelin/math/SafeMath.sol";
import  {IERC20} from "../../../dependencies/openzeppelin/token/ERC20/IERC20.sol";

import {InstrumentReserveLogic} from './InstrumentReserveLogic.sol';
import {GenericLogic} from './GenericLogic.sol';

import {WadRayMath} from '../math/WadRayMath.sol';
import {PercentageMath} from '../math/PercentageMath.sol';

import {SafeERC20} from '../../../dependencies/openzeppelin/token/ERC20/SafeERC20.sol';
import {InstrumentConfiguration} from '../configuration/InstrumentConfiguration.sol';
import {UserConfiguration} from '../configuration/UserConfiguration.sol';
import {Errors} from '../helpers/Errors.sol';
import {Helpers} from '../helpers/Helpers.sol';
import {IInstrumentInterestRateStrategy} from "../../../../interfaces/lendingProtocol/IInstrumentInterestRateStrategy.sol";
import {DataTypes} from '../types/DataTypes.sol';

/**
 * @title ValidationLogic library
 * @author Aave
 * @notice Implements functions to validate the different actions of the protocol
 */
library ValidationLogic {

    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    using InstrumentReserveLogic for DataTypes.InstrumentData;
    using SafeERC20 for IERC20;
    using InstrumentConfiguration for DataTypes.InstrumentConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 public constant REBALANCE_UP_LIQUIDITY_RATE_THRESHOLD = 4000;
    uint256 public constant REBALANCE_UP_USAGE_RATIO_THRESHOLD = 0.95 * 1e27; //usage ratio of 95%

    /**
    * @dev Validates a deposit action
    * @param instrument The instrument object on which the user is depositing
    * @param amount The amount to be deposited
    */
    function validateDeposit(DataTypes.InstrumentData storage instrument, uint256 amount) external view {
        (bool isActive, bool isFrozen, , ) = instrument.configuration.getFlags();

        require(amount != 0, "Amount needs to be greater than 0");
        require(isActive, "Instrument not Active");
        require(!isFrozen, "Instrument Frozen");
    }

    /**
    * @dev Validates a withdraw action
    * @param instrumentAddress The address of the instrument
    * @param amount The amount to be withdrawn
    * @param userBalance The balance of the user
    * @param instrumentsData The instruments state
    * @param userConfig The user configuration
    * @param instruments The addresses of the instruments
    * @param instrumentsCount The number of instruments
    * @param oracle The price oracle
    */
    function validateWithdraw( address instrumentAddress, uint256 amount, uint256 userBalance, mapping(address => DataTypes.InstrumentData) storage instrumentsData, DataTypes.UserConfigurationMap storage userConfig, mapping(uint256 => address) storage instruments, uint256 instrumentsCount, address oracle ) external view {
        require(amount != 0, "Amount needs to be greater than 0");
        require(amount <= userBalance, "NOT ENOUGH AVAILABLE USER BALANCE");

        (bool isActive, , , ) = instrumentsData[instrumentAddress].configuration.getFlags();
        require(isActive, "Instrument not Active");

        require( GenericLogic.balanceDecreaseAllowed( instrumentAddress, msg.sender, amount, instrumentsData, userConfig, instruments, instrumentsCount, oracle ), "TRANSFER NOT ALLOWED" );
    }

    struct ValidateBorrowLocalVars {
        uint256 principalBorrowBalance;
        uint256 currentLtv;
        uint256 currentLiquidationThreshold;
        uint256 requestedBorrowAmountETH;
        uint256 amountOfCollateralNeededETH;
        uint256 userCollateralBalanceETH;
        uint256 userBorrowBalanceETH;
        uint256 borrowBalanceIncrease;
        uint256 currentInstrumentStableRate;
        uint256 availableLiquidity;
        uint256 finalUserBorrowRate;
        uint256 healthFactor;
        DataTypes.InterestRateMode rateMode;
        bool healthFactorBelowThreshold;
        bool isActive;
        bool isFrozen;
        bool borrowingEnabled;
        bool stableRateBorrowingEnabled;
    }

    /**
    * @dev Validates a borrow action
    * @param asset The address of the asset to borrow
    * @param instrument The instrument state from which the user is borrowing
    * @param userAddress The address of the user
    * @param amount The amount to be borrowed
    * @param amountInETH The amount to be borrowed, in ETH
    * @param interestRateMode The interest rate mode at which the user is borrowing
    * @param maxStableLoanPercent The max amount of the liquidity that can be borrowed at stable rate, in percentage
    * @param instrumentsData The state of all the instruments
    * @param userConfig The state of the user for the specific instrument
    * @param instruments The addresses of all the active instruments
    * @param oracle The price oracle
    */

    function validateBorrow( address asset, DataTypes.InstrumentData storage instrument, address userAddress, uint256 amount, uint256 amountInETH, uint256 interestRateMode, uint256 maxStableLoanPercent, mapping(address => DataTypes.InstrumentData) storage instrumentsData, DataTypes.UserConfigurationMap storage userConfig,  mapping(uint256 => address) storage instruments, uint256 instrumentsCount, address oracle  ) external view {
        ValidateBorrowLocalVars memory vars;

        (vars.isActive, vars.isFrozen, vars.borrowingEnabled, vars.stableRateBorrowingEnabled) = instrument.configuration.getFlags();

        require(vars.isActive, "Instrument not Active");
        require(!vars.isFrozen, "Instrument Frozen");
        require(amount != 0, "Amount needs to be greater than 0");

        require(vars.borrowingEnabled, "Borrowing not enabled");

        //validate interest rate mode
        require( uint256(DataTypes.InterestRateMode.VARIABLE) == interestRateMode || uint256(DataTypes.InterestRateMode.STABLE) == interestRateMode, "INVALID INTEREST RATE MODE SELECTED" );

        (vars.userCollateralBalanceETH,vars.userBorrowBalanceETH,vars.currentLtv,vars.currentLiquidationThreshold,vars.healthFactor) = GenericLogic.calculateUserAccountData( userAddress, instrumentsData, userConfig, instruments, instrumentsCount, oracle );

        require(vars.userCollateralBalanceETH > 0, "Collateral Balance is 0");

        require( vars.healthFactor > GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD, "Health Factor less than Liquidation threshold" );

        //add the current already borrowed amount to the amount requested to calculate the total collateral needed.
        vars.amountOfCollateralNeededETH = vars.userBorrowBalanceETH.add(amountInETH).percentDiv( vars.currentLtv  ); //LTV is calculated in percentage

        require( vars.amountOfCollateralNeededETH <= vars.userCollateralBalanceETH, "Not sufficient collateral present");

        /**
        * Following conditions need to be met if the user is borrowing at a stable rate:
        * 1. Instrument must be enabled for stable rate borrowing
        * 2. Users cannot borrow from the reserve if their collateral is (mostly) the same currency
        *    they are borrowing, to prevent abuses.
        * 3. Users will be able to borrow only a portion of the total available liquidity
        **/

        if (vars.rateMode == DataTypes.InterestRateMode.STABLE) {
        //check if the borrow mode is stable and if stable rate borrowing is enabled on this instrument

        require(vars.stableRateBorrowingEnabled, "Stable Borrow not enabled.");

        require( !userConfig.isUsingAsCollateral(instrument.id) || instrument.configuration.getLtv() == 0 || amount > IERC20(instrument.iTokenAddress).balanceOf(userAddress), "COLLATERAL SAME AS BORROWING CURRENCY" );

        vars.availableLiquidity = IERC20(asset).balanceOf(instrument.iTokenAddress);

        //calculate the max available loan size in stable rate mode as a percentage of the available liquidity
        uint256 maxLoanSizeStable = vars.availableLiquidity.percentMul(maxStableLoanPercent);

        require(amount <= maxLoanSizeStable, "AMOUNT BIGGER THAN MAX LOAN SIZE STABLE" );
        }
    }

    /**
    * @dev Validates a repay action
    * @param instrument The instrument state from which the user is repaying
    * @param amountSent The amount sent for the repayment. Can be an actual value or uint(-1)
    * @param onBehalfOf The address of the user msg.sender is repaying for
    * @param stableDebt The borrow balance of the user
    * @param variableDebt The borrow balance of the user
    */
    function validateRepay( DataTypes.InstrumentData storage instrument, uint256 amountSent, DataTypes.InterestRateMode rateMode, address onBehalfOf, uint256 stableDebt, uint256 variableDebt) external view {
        bool isActive = instrument.configuration.getActive();

        require(isActive, "Instrument not Active");
        require(amountSent > 0, "Amount needs to be greater than 0");
        require( (stableDebt > 0 &&  DataTypes.InterestRateMode(rateMode) == DataTypes.InterestRateMode.STABLE) ||  (variableDebt > 0 &&  DataTypes.InterestRateMode(rateMode) == DataTypes.InterestRateMode.VARIABLE),  "NO DEBT OF SELECTED TYPE" );
        require( amountSent != uint256(-1) || msg.sender == onBehalfOf, "NO EXPLICIT AMOUNT TO REPAY ON BEHALF" );
    }

    /**
    * @dev Validates a swap of borrow rate mode.
    * @param instrument The instrument state on which the user is swapping the rate
    * @param userConfig The user instruments configuration
    * @param stableDebt The stable debt of the user
    * @param variableDebt The variable debt of the user
    * @param currentRateMode The rate mode of the borrow
    */
    function validateSwapRateMode( DataTypes.InstrumentData storage instrument, DataTypes.UserConfigurationMap storage userConfig, uint256 stableDebt, uint256 variableDebt, DataTypes.InterestRateMode currentRateMode) external view {
        (bool isActive, bool isFrozen, , bool stableRateEnabled) = instrument.configuration.getFlags();

        require(isActive, "Instrument not Active");
        require(!isFrozen, "Instrument Frozen");

        if (currentRateMode == DataTypes.InterestRateMode.STABLE) {
            require(stableDebt > 0, "NO STABLE RATE LOAN IN INSTRUMENT");
        } 
        else if (currentRateMode == DataTypes.InterestRateMode.VARIABLE) {
            require(variableDebt > 0, "NO VARIABLE RATE LOAN IN INSTRUMENT");
            /**
            * user wants to swap to stable, before swapping we need to ensure that
            * 1. stable borrow rate is enabled on the instrument
            * 2. user is not trying to abuse the instrument by depositing
            * more collateral than he is borrowing, artificially lowering
            * the interest rate, borrowing at variable, and switching to stable
            **/
            require(stableRateEnabled, " STABLE BORROWING NOT ENABLED");
            require(!userConfig.isUsingAsCollateral(instrument.id) || instrument.configuration.getLtv() == 0 || stableDebt.add(variableDebt) > IERC20(instrument.iTokenAddress).balanceOf(msg.sender), "COLLATERAL SAME AS BORROWING CURRENCY" );
        } 
        else {
            revert("INVALID INTEREST RATE MODE SELECTED");
        }
    }

    /**
    * @dev Validates a stable borrow rate rebalance action
    * @param instrument The instrument state on which the user is getting rebalanced
    * @param instrumentAddress The address of the instrument
    * @param stableDebtToken The stable debt token instance
    * @param variableDebtToken The variable debt token instance
    * @param iTokenAddress The address of the aToken contract
    */
    function validateRebalanceStableBorrowRate( DataTypes.InstrumentData storage instrument,  address instrumentAddress, IERC20 stableDebtToken, IERC20 variableDebtToken, address iTokenAddress) external view {
        (bool isActive, , , ) = instrument.configuration.getFlags();

        require(isActive, "Instrument not Active");

        //if the usage ratio is below 95%, no rebalances are needed
        uint256 totalDebt = stableDebtToken.totalSupply().add(variableDebtToken.totalSupply()).wadToRay();
        uint256 availableLiquidity = IERC20(instrumentAddress).balanceOf(iTokenAddress).wadToRay();
        uint256 usageRatio = totalDebt == 0 ? 0 : totalDebt.rayDiv(availableLiquidity.add(totalDebt));

        //if the liquidity rate is below REBALANCE_UP_THRESHOLD of the max variable APR at 95% usage, then we allow rebalancing of the stable rate positions.

        uint256 currentLiquidityRate = instrument.currentLiquidityRate;
        uint256 maxVariableBorrowRate = IInstrumentInterestRateStrategy(instrument.interestRateStrategyAddress).getMaxVariableBorrowRate();

        require( usageRatio >= REBALANCE_UP_USAGE_RATIO_THRESHOLD && currentLiquidityRate <= maxVariableBorrowRate.percentMul(REBALANCE_UP_LIQUIDITY_RATE_THRESHOLD), "LP INTEREST RATE REBALANCE CONDITIONS NOT MET");
    }

    /**
    * @dev Validates the action of setting an asset as collateral
    * @param instrument The state of the instrument that the user is enabling or disabling as collateral
    * @param instrumentAddress The address of the instrument
    * @param instrumentsData The data of all the instruments
    * @param userConfig The state of the user for the specific instrument
    * @param instruments The addresses of all the active instruments
    * @param oracle The price oracle
    */
    function validateSetUseInstrumentAsCollateral(  DataTypes.InstrumentData storage instrument, address instrumentAddress, bool useAsCollateral, mapping(address => DataTypes.InstrumentData) storage instrumentsData, DataTypes.UserConfigurationMap storage userConfig, mapping(uint256 => address) storage instruments,  uint256 instrumentsCount, address oracle) external view {
        uint256 underlyingBalance = IERC20(instrument.iTokenAddress).balanceOf(msg.sender);

        require(underlyingBalance > 0, " UNDERLYING BALANCE NOT GREATER THAN 0");
        require( useAsCollateral ||  GenericLogic.balanceDecreaseAllowed(instrumentAddress,msg.sender,underlyingBalance,instrumentsData,userConfig,instruments,instrumentsCount,oracle), "DEPOSIT ALREADY IN USE" );
    }

    /**
    * @dev Validates a flashloan action
    * @param assets The assets being flashborrowed
    * @param amounts The amounts for each asset being borrowed
    **/
    function validateFlashloan(address[] memory assets, uint256[] memory amounts) internal pure {
        require(assets.length == amounts.length, "INCONSISTENT FLASHLOAN PARAMS");
    }

    /**
    * @dev Validates the liquidation action
    * @param collateralInstrument The instrument data of the collateral
    * @param principalInstrument The instrument data of the principal
    * @param userConfig The user configuration
    * @param userHealthFactor The user's health factor
    * @param userStableDebt Total stable debt balance of the user
    * @param userVariableDebt Total variable debt balance of the user
    **/
    function validateLiquidationCall( DataTypes.InstrumentData storage collateralInstrument, DataTypes.InstrumentData storage principalInstrument, DataTypes.UserConfigurationMap storage userConfig, uint256 userHealthFactor, uint256 userStableDebt, uint256 userVariableDebt ) internal view returns (uint256, string memory) {

        if ( !collateralInstrument.configuration.getActive() || !principalInstrument.configuration.getActive() ) {
            return (  uint256(Errors.CollateralManagerErrors.NO_ACTIVE_INSTRUMENT),  "Instrument not Active" );
        }

        if (userHealthFactor >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD) {
            return ( uint256(Errors.CollateralManagerErrors.HEALTH_FACTOR_ABOVE_THRESHOLD), "HEALTH FACTOR NOT BELOW THRESHOLD" );
        }

        bool isCollateralEnabled = collateralInstrument.configuration.getLiquidationThreshold() > 0 && userConfig.isUsingAsCollateral(collateralInstrument.id);

        //if collateral isn't enabled as collateral by user, it cannot be liquidated
        if (!isCollateralEnabled) {
            return ( uint256(Errors.CollateralManagerErrors.COLLATERAL_CANNOT_BE_LIQUIDATED), "COLLATERAL CANNOT BE LIQUIDATED" );
        }

        if (userStableDebt == 0 && userVariableDebt == 0) {
            return ( uint256(Errors.CollateralManagerErrors.CURRRENCY_NOT_BORROWED), "SPECIFIED CURRENCY NOT BORROWED BY USER" );
        }

        return (uint256(Errors.CollateralManagerErrors.NO_ERROR), "NO ERRORS");
    }

    /**
    * @dev Validates an aToken transfer
    * @param from The user from which the aTokens are being transferred
    * @param instrumentsData The state of all the instruments
    * @param userConfig The state of the user for the specific instrument
    * @param instruments The addresses of all the active instruments
    * @param oracle The price oracle
    */
    function validateTransfer( address from, mapping(address => DataTypes.InstrumentData) storage instrumentsData, DataTypes.UserConfigurationMap storage userConfig, mapping(uint256 => address) storage instruments, uint256 instrumentsCount, address oracle ) internal view {
        (, , , , uint256 healthFactor) = GenericLogic.calculateUserAccountData( from,  instrumentsData,  userConfig,  instruments,  instrumentsCount,  oracle );
        require( healthFactor >= GenericLogic.HEALTH_FACTOR_LIQUIDATION_THRESHOLD, "TRANSFER NOT ALLOWED" );
    }
}