// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {IGlobalAddressesProvider} from "../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";
import {VersionedInitializable} from "../dependencies/upgradability/VersionedInitializable.sol";
import {SafeERC20} from '../dependencies/openzeppelin/token/ERC20/SafeERC20.sol';
import {IERC20} from '../dependencies/openzeppelin/token/ERC20/IERC20.sol';

import {UserConfiguration} from './libraries/configuration/UserConfiguration.sol';
import {InstrumentReserveLogic} from './libraries/logic/InstrumentReserveLogic.sol';
import {InstrumentConfiguration} from './libraries/configuration/InstrumentConfiguration.sol';
import {GenericLogic} from "./libraries/logic/GenericLogic.sol";
import {Helpers} from "./libraries/helpers/Helpers.sol";
import {ValidationLogic} from "./libraries/logic/ValidationLogic.sol";
import {WadRayMath} from './libraries/math/WadRayMath.sol';
import {IFlashLoanReceiver} from "./flashLoan/interfaces/IFlashLoanReceiver.sol";
import {IFeeProviderLendingPool} from "../../interfaces/lendingProtocol/IFeeProviderLendingPool.sol";

import {SafeMath} from "../dependencies/openzeppelin/math/SafeMath.sol";
import {PercentageMath} from './libraries/math/PercentageMath.sol';
import {Errors} from './libraries/helpers/Errors.sol';
import {DataTypes} from './libraries/types/DataTypes.sol';



import {LendingPoolStorage} from './LendingPoolStorage.sol';
import {IPriceOracleGetter} from '../../interfaces/IPriceOracleGetter.sol';
import {IIToken} from "../../interfaces/lendingProtocol/IIToken.sol";
import {IStableDebtToken} from "../../interfaces/lendingProtocol/IStableDebtToken.sol";
import {IVariableDebtToken} from "../../interfaces/lendingProtocol/IVariableDebtToken.sol";
import {ILendingPoolLiquidationManager} from "../../interfaces/lendingProtocol/ILendingPoolLiquidationManager.sol";
import {ISIGHHarvestDebtToken} from '../../interfaces/lendingProtocol/ISIGHHarvestDebtToken.sol';


/**
 * @title LendingPoolLiquidationManager contract
 * @author Aave
 * @dev Implements actions involving management of collateral in the protocol, the main one being the liquidations
 * IMPORTANT This contract will run always via DELEGATECALL, through the LendingPool, so the chain of inheritance
 * is the same as the LendingPool, to have compatible storage layouts
 **/
contract LendingPoolLiquidationManager is ILendingPoolLiquidationManager, VersionedInitializable, LendingPoolStorage {

  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using WadRayMath for uint256;
  using PercentageMath for uint256;

  using InstrumentReserveLogic for DataTypes.InstrumentData;
  using InstrumentConfiguration for DataTypes.InstrumentConfigurationMap;
  using UserConfiguration for DataTypes.UserConfigurationMap;


  uint256 internal constant LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000;

  event PlatformFeeLiquidated(address user,address collateralAsset,address debtAsset,uint userPlatformFee,uint maxLiquidatablePlatformFee,uint platformFeeLiquidated,uint maxCollateralToLiquidateForPlatformFee );
  event ReserveFeeLiquidated(address user,address collateralAsset,address debtAsset,uint userReserveFee,uint maxLiquidatableReserveFee,uint reserveFeeLiquidated,uint maxCollateralToLiquidateForReserveFee );

    
  struct LiquidationCallLocalVars {
    uint256 userCollateralBalance;
    uint256 userStableDebt;
    uint256 userVariableDebt;
    uint256 maxLiquidatableDebt;
    uint256 actualDebtToLiquidate;
    uint256 liquidationRatio;
    uint256 maxAmountCollateralToLiquidate;
    uint256 userStableRate;
    uint256 maxCollateralToLiquidate;
    uint256 debtAmountNeeded;
    uint256 healthFactor;
    uint256 liquidatorPreviousITokenBalance;
    IIToken collateralItoken;
    bool isCollateralEnabled;
    DataTypes.InterestRateMode borrowRateMode;
    uint256 errorCode;
    string errorMsg;
      
    uint userPlatformFee;
    uint userReserveFee;
    uint maxLiquidatablePlatformFee;
    uint maxLiquidatableReserveFee;

    uint maxCollateralToLiquidateForPlatformFee;
    uint maxCollateralToLiquidateForReserveFee;
    uint platformFeeLiquidated;
    uint reserveFeeLiquidated;
  }

    uint256 public constant LIQUIDATION_MANAGER_REVISION = 0x1;             // NEEDED AS PART OF UPGRADABLE CONTRACTS FUNCTIONALITY ( VersionedInitializable )
    uint256 public constant FLASHLOAN_PREMIUM_TOTAL = 90;

    // as the contract extends the VersionedInitializable contract to match the state of the LendingPool contract, the getRevision() function is needed.
    function getRevision() internal override pure returns (uint256) {
        return LIQUIDATION_MANAGER_REVISION;
    }


  /**
   * @dev Function is invoked by the proxy contract when the LendingPool contract is added to the
   * LendingPoolAddressesProvider of the market.
   * - Caching the address of the LendingPoolAddressesProvider in order to reduce gas consumption
   *   on subsequent operations
   * @param provider The address of the LendingPoolAddressesProvider
   **/
  constructor(IGlobalAddressesProvider provider)  {
    addressesProvider = provider;
  }
  
  

// #############################################################################################################################################
// ######  LIQUIDATION FUNCTION --> Anyone can call this function to liquidate the position of the user whose position can be liquidated  ######
// #############################################################################################################################################

    /**
    * @dev users can invoke this function to liquidate an undercollateralized position.
    * @param collateralAsset the address of the collateral to liquidated
    * @param debtAsset the address of the principal instrument
    * @param user the address of the borrower
    * @param debtToCover the amount of principal that the liquidator wants to repay
    * @param receiveIToken true if the liquidators wants to receive the iTokens, false if he wants to receive the underlying asset directly
    **/
    function liquidationCall( address collateralAsset, address debtAsset, address user, uint256 debtToCover, bool receiveIToken ) external override returns (uint256, string memory) {

        DataTypes.InstrumentData storage collateralInstrument = _instruments[collateralAsset];
        DataTypes.InstrumentData storage debtInstrument = _instruments[debtAsset];
        DataTypes.UserConfigurationMap storage userConfig = _usersConfig[user];

        LiquidationCallLocalVars memory vars;        // Usage of a memory struct of vars to avoid "Stack too deep" errors due to local variables

        (, , , , vars.healthFactor) = GenericLogic.calculateUserAccountData( user,_instruments, userConfig,_instrumentsList,_instrumentsCount, addressesProvider.getPriceOracle() );
        (vars.userStableDebt, vars.userVariableDebt) = Helpers.getUserCurrentDebt(user, debtInstrument);
        (vars.errorCode, vars.errorMsg) = ValidationLogic.validateLiquidationCall( collateralInstrument, debtInstrument, userConfig, vars.healthFactor, vars.userStableDebt, vars.userVariableDebt );

        if (Errors.CollateralManagerErrors(vars.errorCode) != Errors.CollateralManagerErrors.NO_ERROR) {
            return (vars.errorCode, vars.errorMsg);
        }

        vars.collateralItoken = IIToken(collateralInstrument.iTokenAddress);
        vars.userCollateralBalance = vars.collateralItoken.balanceOf(user);

        vars.maxLiquidatableDebt = vars.userStableDebt.add(vars.userVariableDebt).percentMul(  LIQUIDATION_CLOSE_FACTOR_PERCENT );
        vars.actualDebtToLiquidate = debtToCover > vars.maxLiquidatableDebt ? vars.maxLiquidatableDebt : debtToCover;

        (  vars.maxCollateralToLiquidate,  vars.debtAmountNeeded) = _calculateAvailableCollateralToLiquidate( collateralInstrument, debtInstrument, collateralAsset, debtAsset, vars.actualDebtToLiquidate, vars.userCollateralBalance );

    // ###########################

        // PLATFORM FEE
        vars.userPlatformFee = ISIGHHarvestDebtToken(debtInstrument.stableDebtTokenAddress).getPlatformFee(user);
        vars.maxLiquidatablePlatformFee = vars.userPlatformFee.percentMul(LIQUIDATION_CLOSE_FACTOR_PERCENT);

        // RESERVE FEE
        vars.userReserveFee = ISIGHHarvestDebtToken(debtInstrument.stableDebtTokenAddress).getReserveFee(user);
        vars.maxLiquidatableReserveFee = vars.userReserveFee.percentMul(LIQUIDATION_CLOSE_FACTOR_PERCENT);


        // Platform FEE RELATED
        if (vars.maxLiquidatablePlatformFee > 0 &&  vars.userCollateralBalance >= vars.maxCollateralToLiquidate  ) {
            (  vars.maxCollateralToLiquidateForPlatformFee,  vars.platformFeeLiquidated) = _calculateAvailableCollateralToLiquidate( collateralInstrument, debtInstrument, collateralAsset, debtAsset, vars.maxLiquidatablePlatformFee, vars.userCollateralBalance.sub(vars.maxCollateralToLiquidate) );
        }

        // Reserve FEE RELATED
        if (vars.maxLiquidatableReserveFee > 0  && vars.userCollateralBalance >= vars.maxCollateralToLiquidate.add(vars.maxCollateralToLiquidateForPlatformFee) ) {
            (  vars.maxCollateralToLiquidateForReserveFee,  vars.reserveFeeLiquidated) = _calculateAvailableCollateralToLiquidate( collateralInstrument, debtInstrument, collateralAsset, debtAsset, vars.maxLiquidatableReserveFee, vars.userCollateralBalance.sub(vars.maxCollateralToLiquidate).sub(vars.maxCollateralToLiquidateForPlatformFee) );
        }

    // ###########################

        // If debtAmountNeeded < actualDebtToLiquidate, there isn't enough collateral to cover the actual amount that is being liquidated, hence we liquidate a smaller amount
        if (vars.debtAmountNeeded < vars.actualDebtToLiquidate) {
            vars.actualDebtToLiquidate = vars.debtAmountNeeded;
        }

        // If the liquidator reclaims the underlying asset, we make sure there is enough available liquidity in the collateral instrument reserve
        if (!receiveIToken) {
            uint256 currentAvailableCollateral = IERC20(collateralAsset).balanceOf(address(vars.collateralItoken));
            if (currentAvailableCollateral < vars.maxCollateralToLiquidate) {
                return (  uint256(Errors.CollateralManagerErrors.NOT_ENOUGH_LIQUIDITY),"NOT ENOUGH LIQUIDITY TO LIQUIDATE");
            }
        }

//        debtInstrument.updateState(sighPayAggregator);

        if (vars.userVariableDebt >= vars.actualDebtToLiquidate) {
            IVariableDebtToken(debtInstrument.variableDebtTokenAddress).burn( user, vars.actualDebtToLiquidate, debtInstrument.variableBorrowIndex );
        }
        else {      // If the user doesn't have variable debt, no need to try to burn variable debt tokens
            if (vars.userVariableDebt > 0) {
                IVariableDebtToken(debtInstrument.variableDebtTokenAddress).burn( user, vars.userVariableDebt, debtInstrument.variableBorrowIndex );
            }
            IStableDebtToken(debtInstrument.stableDebtTokenAddress).burn( user, vars.actualDebtToLiquidate.sub(vars.userVariableDebt) );
        }

//        debtInstrument.updateInterestRates( debtAsset, debtInstrument.iTokenAddress, vars.actualDebtToLiquidate, 0 );

        if (receiveIToken) {
            vars.liquidatorPreviousITokenBalance = IERC20(vars.collateralItoken).balanceOf(msg.sender);
            vars.collateralItoken.transferOnLiquidation(user, msg.sender, vars.maxCollateralToLiquidate);

            if (vars.liquidatorPreviousITokenBalance == 0) {
                DataTypes.UserConfigurationMap storage liquidatorConfig = _usersConfig[msg.sender];
                liquidatorConfig.setUsingAsCollateral(collateralInstrument.id, true);
                emit InstrumentUsedAsCollateralEnabled(collateralAsset, msg.sender);
            }
        }
        else {
            collateralInstrument.updateState(sighPayAggregator);
            collateralInstrument.updateInterestRates( collateralAsset, address(vars.collateralItoken), 0, vars.maxCollateralToLiquidate);

            // Burn the equivalent amount of aToken, sending the underlying to the liquidator
            vars.collateralItoken.burn(user, msg.sender, vars.maxCollateralToLiquidate, collateralInstrument.liquidityIndex);
        }

        // If the collateral being liquidated is equal to the user balance, we set the currency as not being used as collateral anymore
        if (vars.maxCollateralToLiquidate == vars.userCollateralBalance) {
            userConfig.setUsingAsCollateral(collateralInstrument.id, false);
            emit InstrumentUsedAsCollateralDisabled(collateralAsset, user);
        }

        // Transfers the debt asset being repaid to the iToken, where the liquidity is kept
        IERC20(debtAsset).safeTransferFrom( msg.sender, debtInstrument.iTokenAddress, vars.actualDebtToLiquidate);

        // Transfer liquidated Platform fee (collateral) to the SIGH Finance Fee Collector address
        if (vars.platformFeeLiquidated > 0) {
            collateralInstrument.updateState(sighPayAggregator);
            collateralInstrument.updateInterestRates( collateralAsset, address(vars.collateralItoken), 0, vars.maxCollateralToLiquidateForPlatformFee);
            vars.collateralItoken.burn(user, platformFeeCollector , vars.maxCollateralToLiquidateForPlatformFee, collateralInstrument.liquidityIndex);
            ISIGHHarvestDebtToken(debtInstrument.stableDebtTokenAddress).updatePlatformFee(user,0,vars.platformFeeLiquidated);
            emit PlatformFeeLiquidated(user, collateralAsset, debtAsset, vars.userPlatformFee, vars.maxLiquidatablePlatformFee, vars.platformFeeLiquidated, vars.maxCollateralToLiquidateForPlatformFee );
        }

        // Transfer liquidated Reserve fee (collateral) to the SIGH Finance Pay aggregator address
        if (vars.reserveFeeLiquidated > 0) {
            collateralInstrument.updateState(sighPayAggregator);
            collateralInstrument.updateInterestRates( collateralAsset, address(vars.collateralItoken), 0, vars.maxCollateralToLiquidateForReserveFee);
            vars.collateralItoken.burn(user, sighPayAggregator , vars.maxCollateralToLiquidateForReserveFee, collateralInstrument.liquidityIndex);
            ISIGHHarvestDebtToken(debtInstrument.stableDebtTokenAddress).updateReserveFee(user,0,vars.reserveFeeLiquidated);
            emit ReserveFeeLiquidated(user, collateralAsset, debtAsset, vars.userReserveFee, vars.maxLiquidatableReserveFee, vars.reserveFeeLiquidated, vars.maxCollateralToLiquidateForReserveFee );
        }


        emit LiquidationCall(collateralAsset, debtAsset, user, vars.actualDebtToLiquidate, vars.maxCollateralToLiquidate, msg.sender, receiveIToken);

        return (uint256(Errors.CollateralManagerErrors.NO_ERROR), Errors.LPCM_NO_ERRORS);
    }






  struct AvailableCollateralToLiquidateLocalVars {
    uint256 userCompoundedBorrowBalance;
    uint256 liquidationBonus;
    uint256 collateralPrice;
    uint256 debtAssetPrice;
    uint256 maxAmountCollateralToLiquidate;
    uint256 debtAssetDecimals;
    uint256 collateralDecimals;
  }

    /**
    * @dev Calculates how much of a specific collateral can be liquidated, given a certain amount of debt asset.
    * - This function needs to be called after all the checks to validate the liquidation have been performed, otherwise it might fail.
    * @param collateralInstrument The data of the collateral reserve
    * @param debtInstrument The data of the debt reserve
    * @param collateralAsset The address of the underlying asset used as collateral, to receive as result of the liquidation
    * @param debtAsset The address of the underlying borrowed asset to be repaid with the liquidation
    * @param debtToCover The debt amount of borrowed `asset` the liquidator wants to cover
    * @param userCollateralBalance The collateral balance for the specific `collateralAsset` of the user being liquidated
    * @return collateralAmount: The maximum amount that is possible to liquidate given all the liquidation constraints  (user balance, close factor)
    *         debtAmountNeeded: The amount to repay with the liquidation
    **/
    function _calculateAvailableCollateralToLiquidate(  DataTypes.InstrumentData storage collateralInstrument,  DataTypes.InstrumentData storage debtInstrument,  address collateralAsset,  address debtAsset, uint256 debtToCover, uint256 userCollateralBalance ) internal view returns (uint256, uint256) {
        uint256 collateralAmount = 0;
        uint256 debtAmountNeeded = 0;
        IPriceOracleGetter oracle = IPriceOracleGetter(addressesProvider.getPriceOracle());

        AvailableCollateralToLiquidateLocalVars memory vars;

        vars.collateralPrice = oracle.getAssetPrice(collateralAsset);
        vars.debtAssetPrice = oracle.getAssetPrice(debtAsset);

        (, , vars.liquidationBonus, vars.collateralDecimals, ) = collateralInstrument.configuration.getParams();
        vars.debtAssetDecimals = debtInstrument.configuration.getDecimals();

        // This is the maximum possible amount of the selected collateral that can be liquidated, given the max amount of liquidatable debt
        vars.maxAmountCollateralToLiquidate = vars.debtAssetPrice.mul(debtToCover).mul(10**vars.collateralDecimals).percentMul(vars.liquidationBonus).div( vars.collateralPrice.mul(10**vars.debtAssetDecimals) );

        if (vars.maxAmountCollateralToLiquidate > userCollateralBalance) {
            collateralAmount = userCollateralBalance;
            debtAmountNeeded = vars.collateralPrice.mul(collateralAmount).mul(10**vars.debtAssetDecimals).div(vars.debtAssetPrice.mul(10**vars.collateralDecimals)).percentDiv(vars.liquidationBonus);
        }
        else {
            collateralAmount = vars.maxAmountCollateralToLiquidate;
            debtAmountNeeded = debtToCover;
        }
        return (collateralAmount, debtAmountNeeded);
    }
    
    
    
    
    
    
    struct flashLoanVars {
       address iTokenAddress;
       uint256 availableLiquidityBefore;
       uint256 availableLiquidityAfter;
       address feeProvider;
       uint totalFee;
       uint platformFee;
       uint reserveFee;
       IFlashLoanReceiver receiver;
    }
    

    /**
    * @dev allows smartcontracts to access the liquidity of the pool within one transaction,
    * as long as the amount taken plus a fee is returned. NOTE There are security concerns for developers of flashloan receiver contracts
    * that must be kept into consideration. For further details please visit https://developers.aave.com
    * @param _receiver The address of the contract receiving the funds. The receiver should implement the IFlashLoanReceiver interface.
    * @param _instrument the address of the principal instrument
    * @param _amount the amount requested for this flashloan
    **/
    function flashLoan(address user, address _receiver, address _instrument, uint256 _amount, bytes memory _params, uint16 boosterID) external returns (uint256, string memory) {
        flashLoanVars memory vars;
        vars.iTokenAddress = _instruments[_instrument].iTokenAddress;

        // check Liquidity
        vars.availableLiquidityBefore = IERC20(_instrument).balanceOf(vars.iTokenAddress);
        require( vars.availableLiquidityBefore >= _amount, Errors.LIQUIDITY_NOT_AVAILABLE);

        vars.feeProvider = addressesProvider.getFeeProvider();
        (vars.totalFee, vars.platformFee, vars.reserveFee) = IFeeProviderLendingPool(vars.feeProvider).calculateFlashLoanFee(user,_amount,boosterID);    // get flash loan fee

        vars.receiver = IFlashLoanReceiver(_receiver);            //get the FlashLoanReceiver instance
        IIToken(vars.iTokenAddress).transferUnderlyingTo(_receiver, _amount);        //transfer funds to the receiver
        vars.receiver.executeOperation(_instrument, _amount, vars.totalFee, _params);     //execute action of the receiver

        //check that the Fee is returned along with the amount
        vars.availableLiquidityAfter = IERC20(_instrument).balanceOf(vars.iTokenAddress);
        require( vars.availableLiquidityAfter == vars.availableLiquidityBefore.add(vars.totalFee), Errors.INCONCISTENT_BALANCE);

        // _instruments[_instrument].updateState(sighPayAggregator);
        _instruments[_instrument].cumulateToLiquidityIndex( IERC20(vars.iTokenAddress).totalSupply(), vars.reserveFee );
        _instruments[_instrument].updateInterestRates(_instrument, vars.iTokenAddress, _amount.add(vars.reserveFee), 0 );

        IIToken(vars.iTokenAddress).transferUnderlyingTo(platformFeeCollector, vars.platformFee);

        emit FlashLoan(user, _receiver, _instrument, _amount, vars.platformFee, vars.reserveFee, boosterID);
        return (uint256(Errors.CollateralManagerErrors.NO_ERROR), Errors.LPCM_NO_ERRORS);
    }

  
    
    
    
    
}