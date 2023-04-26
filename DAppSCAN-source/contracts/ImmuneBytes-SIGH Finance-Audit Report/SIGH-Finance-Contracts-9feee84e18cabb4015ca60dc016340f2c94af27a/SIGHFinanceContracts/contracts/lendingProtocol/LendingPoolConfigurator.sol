// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import {VersionedInitializable} from "../dependencies/upgradability/VersionedInitializable.sol";
import {InitializableAdminUpgradeabilityProxy} from "../dependencies/upgradability/InitializableAdminUpgradeabilityProxy.sol";

import {IGlobalAddressesProvider} from  "../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";
import {ILendingPool} from "../../interfaces/lendingProtocol/ILendingPool.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import  {IERC20Detailed} from "../dependencies/openzeppelin/token/ERC20/IERC20Detailed.sol";
import {ITokenConfiguration} from "../../interfaces/lendingProtocol/ITokenConfiguration.sol";
import { PercentageMath} from "./libraries/math/PercentageMath.sol";
import { SafeMath} from "../dependencies/openzeppelin/math/SafeMath.sol";
import { InstrumentConfiguration} from "./libraries/configuration/InstrumentConfiguration.sol";
import { DataTypes} from "./libraries/types/DataTypes.sol";

import {ISIGHHarvestDebtToken} from "../../interfaces/lendingProtocol/ISIGHHarvestDebtToken.sol";
import {ISIGHVolatilityHarvesterLendingPool} from "../../interfaces/lendingProtocol/ISIGHVolatilityHarvesterLendingPool.sol";
import {Errors} from './libraries/helpers/Errors.sol';


/**
* @title LendingPoolConfigurator contract
* @author Aave, SIGH Finance (modified by SIGH FINANCE)
* @notice Executes configuration methods on the LendingPoolCore contract. Allows to enable/disable instruments,
* and set different protocol parameters.
**/

contract LendingPoolConfigurator is VersionedInitializable  {

    using SafeMath for uint256;
    using PercentageMath for uint256;
    using InstrumentConfiguration for DataTypes.InstrumentConfigurationMap;

    IGlobalAddressesProvider public globalAddressesProvider;
    ILendingPool public pool;

    mapping (address => address) private sighHarvesterProxies;
// ######################
// ####### EVENTS #######
// ######################


    event InstrumentInitialized(address asset,address iTokenProxyAddress,address stableDebtTokenProxyAddress,address variableDebtTokenProxyAddress,address SIGHHarvesterProxyAddress,address interestRateStrategyAddress,uint8 underlyingAssetDecimals);

    event sighHarvesterImplUpdated(address asset, address newSighHarvesterImpl );
    event VariableDebtTokenUpgraded(address asset, address variableDebtProxyAddress, address variableDebtImplementation);
    event StableDebtTokenUpgraded(address asset, address stableDebtTokenProxyAddress, address stableDebtTokenImplementation);
    event ITokenUpgraded(address asset, address iTokenProxyAddress, address iTokenImplementation);

    /**
    * @dev emitted when a instrument is enabled as collateral.
    * @param _instrument the address of the instrument
    * @param _ltv the loan to value of the asset when used as collateral
    * @param _liquidationThreshold the threshold at which loans using this asset as collateral will be considered undercollateralized
    * @param _liquidationBonus the bonus liquidators receive to liquidate this asset
    **/
    event InstrumentEnabledAsCollateral(  address indexed _instrument,  uint256 _ltv,  uint256 _liquidationThreshold,  uint256 _liquidationBonus );
    event InstrumentDisabledAsCollateral(address indexed _instrument);         // emitted when a instrument is disabled as collateral

    event InstrumentDecimalsUpdated(address _instrument,uint256 decimals);
    event InstrumentCollateralParametersUpdated(address _instrument,uint256 _ltv,  uint256 _liquidationThreshold,  uint256 _liquidationBonus );

    event BorrowingOnInstrumentSwitched(address indexed _instrument, bool switch_ );
    event StableRateOnInstrumentSwitched(address indexed _instrument, bool isEnabled);          // emitted when stable rate borrowing is switched on a instrument
    event InstrumentActivationSwitched(address indexed _instrument, bool switch_ );
    event InstrumentFreezeSwitched(address indexed _instrument, bool isFreezed);                      // emitted when a instrument is freezed

    event ReserveFactorChanged(address _instrument, uint _reserveFactor);      // emitted when a _instrument interest strategy contract is updated
    event InstrumentInterestRateStrategyChanged(address _instrument, address _strategy);      // emitted when a _instrument interest strategy contract is updated
    event ProxyCreated(address instrument, address  sighStreamProxyAddress);

// #############################
// ####### PROXY RELATED #######
// #############################

    uint256 public constant CONFIGURATOR_REVISION = 0x2;

    function getRevision() internal override pure returns (uint256) {
        return CONFIGURATOR_REVISION;
    }

    function initialize(IGlobalAddressesProvider _globalAddressesProvider) public initializer {
        globalAddressesProvider = _globalAddressesProvider;
        pool = ILendingPool(globalAddressesProvider.getLendingPool());
    }

// ########################
// ####### MODIFIER #######
// ########################
    /**
    * @dev only the lending pool manager can call functions affected by this modifier
    **/
    modifier onlyLendingPoolManager {
        require( globalAddressesProvider.getLendingPoolManager() == msg.sender, "The caller must be a lending pool manager" );
        _;
    }

// ################################################################################################
// ####### INITIALIZE A NEW INSTRUMENT (Deploys a new IToken Contract for the INSTRUMENT) #########
// ################################################################################################
  /**
  * @dev Initializes an instrument reserve
  * @param iTokenImpl  The address of the iToken contract implementation
  * @param stableDebtTokenImpl The address of the stable debt token contract
  * @param variableDebtTokenImpl The address of the variable debt token contract
  * @param sighHarvesterAddressImpl The address of the SIGH Harvester contract
  * @param underlyingAssetDecimals The decimals of the reserve underlying asset
  * @param interestRateStrategyAddress The address of the interest rate strategy contract for this reserve
  **/
  function initInstrument(address iTokenImpl, address stableDebtTokenImpl, address variableDebtTokenImpl, address sighHarvesterAddressImpl, uint8 underlyingAssetDecimals, address interestRateStrategyAddress) public onlyLendingPoolManager {
    address asset = ITokenConfiguration(iTokenImpl).UNDERLYING_ASSET_ADDRESS();

    require(address(pool) == ITokenConfiguration(iTokenImpl).POOL(), "INVALID ITOKEN POOL ADDRESS");
    require(address(pool) == ITokenConfiguration(stableDebtTokenImpl).POOL(), "INVALID STABLE DEBT TOKEN POOL ADDRESS");
    require(address(pool) == ITokenConfiguration(variableDebtTokenImpl).POOL(), "INVALID VARIABLE DEBT TOKEN POOL ADDRESS");
    require(asset == ITokenConfiguration(stableDebtTokenImpl).UNDERLYING_ASSET_ADDRESS(), "INVALID STABLE DEBT TOKEN UNDERLYING ADDRESS");
    require(asset == ITokenConfiguration(variableDebtTokenImpl).UNDERLYING_ASSET_ADDRESS(), "INVALID VARIABLE DEBT TOKEN UNDERLYING ADDRESS");

    address iTokenProxyAddress = _initTokenWithProxy(iTokenImpl, underlyingAssetDecimals);                          // Create a proxy contract for IToken
    emit ITokenUpgraded(asset, iTokenProxyAddress, iTokenImpl);

    address stableDebtTokenProxyAddress = _initTokenWithProxy(stableDebtTokenImpl, underlyingAssetDecimals);        // Create a proxy contract for stable Debt Token
    emit StableDebtTokenUpgraded(asset, stableDebtTokenProxyAddress, stableDebtTokenImpl);

    address variableDebtTokenProxyAddress = _initTokenWithProxy(variableDebtTokenImpl, underlyingAssetDecimals);    // Create a proxy contract for variable Debt Token
    emit VariableDebtTokenUpgraded(asset, variableDebtTokenProxyAddress, variableDebtTokenImpl);

    address SIGHHarvesterProxyAddress = setSIGHHarvesterImplInternal(address(globalAddressesProvider),sighHarvesterAddressImpl, asset, iTokenProxyAddress, stableDebtTokenProxyAddress, variableDebtTokenProxyAddress );    // creates a Proxy Contract for the SIGH Harvester
    emit sighHarvesterImplUpdated(asset, sighHarvesterAddressImpl );

    pool.initInstrument(asset, iTokenProxyAddress, stableDebtTokenProxyAddress, variableDebtTokenProxyAddress, interestRateStrategyAddress);

    DataTypes.InstrumentConfigurationMap memory currentConfig = pool.getInstrumentConfiguration(asset);
    currentConfig.setDecimals(underlyingAssetDecimals);
    currentConfig.setActive(true);
    currentConfig.setFrozen(false);
    pool.setConfiguration(asset, currentConfig.data);
    
    ISIGHVolatilityHarvesterLendingPool sighVolatilityHarvester = ISIGHVolatilityHarvesterLendingPool(globalAddressesProvider.getSIGHVolatilityHarvester());

    require( sighVolatilityHarvester.addInstrument( asset, iTokenProxyAddress, stableDebtTokenProxyAddress, variableDebtTokenProxyAddress, SIGHHarvesterProxyAddress, underlyingAssetDecimals ), Errors.VOL_HAR_INIT_FAIL ); // ADDED BY SIGH FINANCE
    require( ISIGHHarvestDebtToken(iTokenProxyAddress).setSIGHHarvesterAddress( SIGHHarvesterProxyAddress ), Errors.IT_INIT_FAIL );
    require( ISIGHHarvestDebtToken(variableDebtTokenProxyAddress).setSIGHHarvesterAddress( SIGHHarvesterProxyAddress ), Errors.VT_INIT_FAIL);
    require( ISIGHHarvestDebtToken(stableDebtTokenProxyAddress).setSIGHHarvesterAddress( SIGHHarvesterProxyAddress ), Errors.ST_INIT_FAIL );


    emit InstrumentInitialized(asset, iTokenProxyAddress, stableDebtTokenProxyAddress, variableDebtTokenProxyAddress, SIGHHarvesterProxyAddress, interestRateStrategyAddress, underlyingAssetDecimals);
  }
    
  /**
  * @dev Updates the iToken implementation for the instrument
  * @param asset The address of the underlying asset of the reserve to be updated
  * @param implementation The address of the new iToken implementation
  **/
  function updateIToken(address asset, address implementation) external onlyLendingPoolManager {
    DataTypes.InstrumentData memory instrumentData = pool.getInstrumentData(asset);
     _upgradeTokenImplementation(asset, instrumentData.iTokenAddress, implementation);
    emit ITokenUpgraded(asset, instrumentData.iTokenAddress, implementation);
  }

  /**
  * @dev Updates the stable debt token implementation for the instrument
  * @param asset The address of the underlying asset of the reserve to be updated
  * @param implementation The address of the new stable debt token implementation
  **/
  function updateStableDebtToken(address asset, address implementation) external onlyLendingPoolManager {
    DataTypes.InstrumentData memory instrumentData = pool.getInstrumentData(asset);
     _upgradeTokenImplementation(asset, instrumentData.stableDebtTokenAddress, implementation);
    emit StableDebtTokenUpgraded(asset, instrumentData.stableDebtTokenAddress, implementation);
  }

  /**
  * @dev Updates the variable debt token implementation for the instrument
  * @param asset The address of the underlying asset of the reserve to be updated
  * @param implementation The address of the new variable debt token implementation
  **/
  function updateVariableDebtToken(address asset, address implementation) external onlyLendingPoolManager {
    DataTypes.InstrumentData memory instrumentData = pool.getInstrumentData(asset);
    _upgradeTokenImplementation(asset, instrumentData.variableDebtTokenAddress, implementation);
    emit VariableDebtTokenUpgraded(asset, instrumentData.variableDebtTokenAddress, implementation);
  }    
    
    /**
     * @dev Updates the SIGH Harvester implementation for the instrument
     * @param asset The address of the underlying asset of the reserve to be updated
     * @param newSighHarvesterImpl The address of the SIGH Harvester implementation
     **/
    function updateSIGHHarvesterForInstrument(  address newSighHarvesterImpl, address asset) external onlyLendingPoolManager {
        DataTypes.InstrumentData memory instrumentData = pool.getInstrumentData(asset);
        updateSIGHHarvesterImplInternal(address(globalAddressesProvider), newSighHarvesterImpl, asset, instrumentData.iTokenAddress, instrumentData.stableDebtTokenAddress, instrumentData.variableDebtTokenAddress );
        emit sighHarvesterImplUpdated(asset, newSighHarvesterImpl );
    }

// ###################################################################################################
// ####### FUNCTIONS TO UPDATE THE LENDING PROTOCOL STATE ####################################
// ###################################################################################################

  /**
  * @dev Enables borrowing on an instrument reserve
  * @param asset The address of the underlying asset
  * @param stableBorrowRateEnabled True if stable borrow rate needs to be enabled by default on this reserve
  **/
  function enableBorrowingOnInstrument(address asset, bool stableBorrowRateEnabled) external onlyLendingPoolManager {
    DataTypes.InstrumentConfigurationMap memory currentConfig = pool.getInstrumentConfiguration(asset);
    currentConfig.setBorrowingEnabled(true);
    currentConfig.setStableRateBorrowingEnabled(stableBorrowRateEnabled);
    pool.setConfiguration(asset, currentConfig.data);
    emit BorrowingOnInstrumentSwitched(asset, true);
    emit StableRateOnInstrumentSwitched(asset, stableBorrowRateEnabled);
  }

  /**
  * @dev Disables borrowing on an instrument reserve
  * @param asset The address of the underlying asset
  **/
  function disableBorrowingOnInstrument(address asset) external onlyLendingPoolManager {
    DataTypes.InstrumentConfigurationMap memory currentConfig = pool.getInstrumentConfiguration(asset);
    currentConfig.setBorrowingEnabled(false);
    pool.setConfiguration(asset, currentConfig.data);
    emit BorrowingOnInstrumentSwitched(asset, false);
  }

  /**
  * @dev Configures the instrument collateralization parameters
  * all the values are expressed in percentages with two decimals of precision. A valid value is 10000, which means 100.00%
  * @param asset The address of the underlying asset of the reserve
  * @param ltv The loan to value of the asset when used as collateral
  * @param liquidationThreshold The threshold at which loans using this asset as collateral will be considered undercollateralized
  * @param liquidationBonus The bonus liquidators receive to liquidate this asset. The values is always above 100%. A value of 105%
  * means the liquidator will receive a 5% bonus
  **/
  function configureInstrumentAsCollateral(address asset, uint256 ltv, uint256 liquidationThreshold, uint256 liquidationBonus) external onlyLendingPoolManager {
    DataTypes.InstrumentConfigurationMap memory currentConfig = pool.getInstrumentConfiguration(asset);

    //validation of the parameters: the LTV can only be lower or equal than the liquidation threshold
    require(ltv <= liquidationThreshold, "INVALID CONFIGURATION");

    if (liquidationThreshold != 0) {
      //liquidation bonus must be bigger than 100.00%, otherwise the liquidator would receive less collateral than needed to cover the debt
      require(liquidationBonus > PercentageMath.PERCENTAGE_FACTOR, "INVALID CONFIGURATION");
      //if threshold * bonus is less than PERCENTAGE_FACTOR, it's guaranteed that at the moment
      //a loan is taken there is enough collateral available to cover the liquidation bonus
      require(liquidationThreshold.percentMul(liquidationBonus) <= PercentageMath.PERCENTAGE_FACTOR, "INVALID CONFIGURATION");
    }
    else {
      require(liquidationBonus == 0, "INVALID CONFIGURATION");
      //if the liquidation threshold is being set to 0,the Instrument is being disabled as collateral. To do so, we need to ensure no liquidity is deposited
      _checkNoLiquidity(asset);
    }

    currentConfig.setLtv(ltv);
    currentConfig.setLiquidationThreshold(liquidationThreshold);
    currentConfig.setLiquidationBonus(liquidationBonus);
    pool.setConfiguration(asset, currentConfig.data);

    emit InstrumentCollateralParametersUpdated(asset, ltv, liquidationThreshold, liquidationBonus);
  }

  /**
  * @dev Enable stable rate borrowing on a Instrument
  * @param asset The address of the underlying asset of the reserve
  **/
  function enableInstrumentStableRate(address asset) external onlyLendingPoolManager {
    DataTypes.InstrumentConfigurationMap memory currentConfig = pool.getInstrumentConfiguration(asset);
    currentConfig.setStableRateBorrowingEnabled(true);
    pool.setConfiguration(asset, currentConfig.data);
    emit StableRateOnInstrumentSwitched(asset, true);
  }

  /**
  * @dev Disable stable rate borrowing on a reserve
  * @param asset The address of the underlying asset of the reserve
  **/
  function disableInstrumentStableRate(address asset) external onlyLendingPoolManager {
    DataTypes.InstrumentConfigurationMap memory currentConfig = pool.getInstrumentConfiguration(asset);
    currentConfig.setStableRateBorrowingEnabled(false);
    pool.setConfiguration(asset, currentConfig.data);
    emit StableRateOnInstrumentSwitched(asset, false);
  }

  /**
  * @dev Activates a Instrument
  * @param asset The address of the underlying asset of the reserve
  **/
  function activateInstrument(address asset) external onlyLendingPoolManager {
    DataTypes.InstrumentConfigurationMap memory currentConfig = pool.getInstrumentConfiguration(asset);
    currentConfig.setActive(true);
    pool.setConfiguration(asset, currentConfig.data);
    emit InstrumentActivationSwitched(asset, true);
  }

  /**
  * @dev Deactivates a Instrument
  * @param asset The address of the underlying asset of the reserve
  **/
  function deactivateInstrument(address asset) external onlyLendingPoolManager {
    _checkNoLiquidity(asset);
    DataTypes.InstrumentConfigurationMap memory currentConfig = pool.getInstrumentConfiguration(asset);
    currentConfig.setActive(false);
    pool.setConfiguration(asset, currentConfig.data);
    emit InstrumentActivationSwitched(asset, false);
  }

  /**
  * @dev Freezes a Instrument. A frozen reserve doesn't allow any new deposit, borrow or rate swap
  *  but allows repayments, liquidations, rate rebalances and withdrawals
  * @param asset The address of the underlying asset of the reserve
  **/
  function freezeInstrument(address asset) external onlyLendingPoolManager {
    DataTypes.InstrumentConfigurationMap memory currentConfig = pool.getInstrumentConfiguration(asset);
    currentConfig.setFrozen(true);
    pool.setConfiguration(asset, currentConfig.data);
    emit InstrumentFreezeSwitched(asset, true);
  }

  /**
  * @dev Unfreezes a Instrument
  * @param asset The address of the underlying asset of the Instrument
  **/
  function unfreezeInstrument(address asset) external onlyLendingPoolManager {
    DataTypes.InstrumentConfigurationMap memory currentConfig = pool.getInstrumentConfiguration(asset);
    currentConfig.setFrozen(false);
    pool.setConfiguration(asset, currentConfig.data);
    emit InstrumentFreezeSwitched(asset, false);
  }
    
  /**
  * @dev Updates the reserve factor of a Instrument
  * @param asset The address of the underlying asset of the reserve
  * @param reserveFactor The new reserve factor of the Instrument
  **/
  function setReserveFactor(address asset, uint256 reserveFactor) external onlyLendingPoolManager {
      
    DataTypes.InstrumentConfigurationMap memory currentConfig = pool.getInstrumentConfiguration(asset);
    currentConfig.setReserveFactor(reserveFactor);
    pool.setConfiguration(asset, currentConfig.data);
    emit ReserveFactorChanged(asset, reserveFactor);
  }

  /**
  * @dev Sets the interest rate strategy of a Instrument
  * @param asset The address of the underlying asset of the reserve
  * @param rateStrategyAddress The new address of the interest strategy contract
  **/
  function setInstrumentInterestRateStrategyAddress(address asset, address rateStrategyAddress) external onlyLendingPoolManager {
    pool.setInstrumentInterestRateStrategyAddress(asset, rateStrategyAddress);
    emit InstrumentInterestRateStrategyChanged(asset, rateStrategyAddress);
  }

  /**
  * @dev pauses or unpauses all the actions of the protocol, including aToken transfers
  * @param val true if protocol needs to be paused, false otherwise
  **/
  function setPoolPause(bool val) external onlyLendingPoolManager {
    pool.setPause(val);
  }



   // refreshes the lending pool configuration to update the cached address
    function refreshLendingPoolConfiguration() external onlyLendingPoolManager {
        pool.refreshConfig();
    }

    function getSighHarvesterAddress(address instrumentAddress) external view returns (address sighHarvesterProxyAddress) {
        return sighHarvesterProxies[instrumentAddress];
    }

// #############################################
// ######  FUNCTION TO UPGRADE THE PROXY #######
// #############################################

    // Create a new Proxy contract for the SIGH harvester contract
    function setSIGHHarvesterImplInternal( address globalAddressProvider, address sighHarvesterAddressImpl, address asset, address iTokenProxyAddress, address stableDebtTokenProxyAddress, address variableDebtTokenProxyAddress ) internal returns (address) {
        bytes memory params = abi.encodeWithSignature("initialize(address,address,address,address,address)", globalAddressProvider, asset, iTokenProxyAddress, stableDebtTokenProxyAddress, variableDebtTokenProxyAddress );            // initialize function is called in the new implementation contract
        InitializableAdminUpgradeabilityProxy proxy = new InitializableAdminUpgradeabilityProxy();
        proxy.initialize(sighHarvesterAddressImpl, address(this), params);
        sighHarvesterProxies[asset] = address(proxy);
        emit ProxyCreated(asset, address(proxy));
        return address(proxy);
    }

    // Update the implementation for the SIGH harvester contract
    function updateSIGHHarvesterImplInternal( address globalAddressProvider, address sighHarvesterAddressImpl, address asset, address iTokenProxyAddress, address stableDebtTokenProxyAddress, address variableDebtTokenProxyAddress ) internal {
        address payable proxyAddress = address( uint160(sighHarvesterProxies[asset] ));
        InitializableAdminUpgradeabilityProxy proxy = InitializableAdminUpgradeabilityProxy(proxyAddress);
        bytes memory params = abi.encodeWithSignature("initialize(address,address,address,address,address)", globalAddressProvider, asset, iTokenProxyAddress, stableDebtTokenProxyAddress, variableDebtTokenProxyAddress );           // initialize function is called in the new implementation contract
        proxy.upgradeToAndCall(sighHarvesterAddressImpl, params);
    }


    // Create a new Proxy contract for the iToken / stable debt token / variable debt token
    function _initTokenWithProxy(address implementation, uint8 decimals) internal returns (address) {
        InitializableAdminUpgradeabilityProxy proxy = new InitializableAdminUpgradeabilityProxy();
        bytes memory params = abi.encodeWithSignature( 'initialize(uint8,string,string)', decimals, IERC20Detailed(implementation).name(), IERC20Detailed(implementation).symbol() );
        proxy.initialize(implementation, params);
        return address(proxy);
    }

    // Update the implementation for the Proxy contract for the iToken / stable debt token / variable debt token
    function _upgradeTokenImplementation(address asset, address proxyAddress, address implementation) internal {
        InitializableAdminUpgradeabilityProxy proxy = InitializableAdminUpgradeabilityProxy(payable(proxyAddress));
        DataTypes.InstrumentConfigurationMap memory configuration = pool.getInstrumentConfiguration(asset);
        (, , , uint256 decimals, ) = configuration.getParamsMemory();
        bytes memory params = abi.encodeWithSignature('initialize(uint8,string,string)', uint8(decimals), IERC20Detailed(implementation).name(), IERC20Detailed(implementation).symbol());
        proxy.upgradeToAndCall(implementation, params);
    }



    function _checkNoLiquidity(address asset) internal view {
      DataTypes.InstrumentData memory instrumentData = pool.getInstrumentData(asset);
      uint256 availableLiquidity = ITokenConfiguration(asset).balanceOf(instrumentData.iTokenAddress);
      require(availableLiquidity == 0 && instrumentData.currentLiquidityRate == 0, "Instrument LIQUIDITY NOT 0");
    }






}