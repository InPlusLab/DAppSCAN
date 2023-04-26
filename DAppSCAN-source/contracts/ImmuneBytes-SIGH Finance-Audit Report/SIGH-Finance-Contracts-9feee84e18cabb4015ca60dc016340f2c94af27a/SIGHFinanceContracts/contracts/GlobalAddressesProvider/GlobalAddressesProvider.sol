// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import "./AddressStorage.sol";
import "../dependencies/upgradability/InitializableAdminUpgradeabilityProxy.sol";

import "../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";

/**
* @title GlobalAddressesProvider contract
* @notice Is the main registry of the protocol. All the different components of the protocol are accessible through the addresses provider.
* @author _astromartian, built upon the Aave protocol's AddressesProviderContract(v1)
**/

contract GlobalAddressesProvider is IGlobalAddressesProvider, AddressStorage {

    bool isSighInitialized;
    bool isNFTBoosterInitialized;

    //#############################################
    //################### EVENTS ##################
    //#############################################
    
    //LendingPool and SIGH Finance Managers
    event PendingSIGHFinanceManagerUpdated( address _pendingSighFinanceManager );
    event SIGHFinanceManagerUpdated( address _sighFinanceManager );
    event PendingLendingPoolManagerUpdated( address _pendingLendingPoolManager );
    event LendingPoolManagerUpdated( address _lendingPoolManager );

    //LendingPool Contracts
    event LendingPoolConfiguratorUpdated(address indexed newAddress);
    event LendingPoolUpdated(address indexed newAddress);
    event LendingPoolLiqAndLoanManagerUpdated(address indexed newAddress);
    event LendingRateOracleUpdated(address indexed newAddress);
    event FeeProviderUpdated(address indexed newAddress);

    //SIGH Finance Contracts
    event SIGHFinanceConfiguratorUpdated(address indexed sighFinanceConfigAddress);       
    event SIGHAddressUpdated(address indexed sighAddress);    
    event SIGHNFTBoosterUpdated(address indexed boosterAddress);
    event SIGHSpeedControllerUpdated(address indexed speedControllerAddress);
    event SIGHVolatilityHarvesterImplUpdated(address indexed newAddress);                   
    event SIGHTreasuryImplUpdated(address indexed newAddress);                           
    event SIGHStakingImplUpdated(address indexed SIGHStakingAddress);                    

    //Contracts which collect Fee & SIGH Pay
    event SIGHFinanceFeeCollectorUpdated(address indexed newAddress);
    event SIGHFinanceSIGHPAYAggregatorUpdated(address indexed newAddress);

    //Price Oracle and general events
    event PriceOracleUpdated(address indexed newAddress);
    event ProxyCreated(bytes32 id, address indexed newAddress);

    //#########################################################
    //################### bytes32 parameters ##################
    //#########################################################
    
    //LendingPool and SIGH Finance Managers    
    bytes32 private constant LENDING_POOL_MANAGER = "LENDING_POOL_MANAGER";                         // MULTISIG ACCOUNT WHICH CONTROLS THE UPDATES TO THE LENDINGPOOL
    bytes32 private constant PENDING_LENDING_POOL_MANAGER = "PENDING_LENDING_POOL_MANAGER";         // MULTISIG ACCOUNT WHICH CONTROLS THE UPDATES TO THE LENDINGPOOL 
    bytes32 private constant SIGH_FINANCE_MANAGER = "SIGH_FINANCE_MANAGER";                         // MULTISIG ACCOUNT WHICH CONTROLS THE UPDATES TO THE SIGH FINANCE
    bytes32 private constant PENDING_SIGH_FINANCE_MANAGER = "PENDING_SIGH_FINANCE_MANAGER";         // MULTISIG ACCOUNT WHICH CONTROLS THE UPDATES TO THE SIGH FINANCE 

    //LendingPool Contracts    
    bytes32 private constant LENDING_POOL_CONFIGURATOR = "LENDING_POOL_CONFIGURATOR";       // CONTROLLED BY LENDINGPOOL MANAGER. MAKES STATE CHANGES RELATED TO LENDING PROTOCOL
    bytes32 private constant LENDING_POOL = "LENDING_POOL";
    bytes32 private constant LENDING_POOL_LIQANDLOAN_MANAGER = "LIQANDLOAN_MANAGER";
    bytes32 private constant LENDING_RATE_ORACLE = "LENDING_RATE_ORACLE";
    bytes32 private constant FEE_PROVIDER = "FEE_PROVIDER";

    //SIGH Finance Contracts
    bytes32 private constant SIGH_FINANCE_CONFIGURATOR = "SIGH_FINANCE_CONFIGURATOR";       // CONTROLLED BY SIGHFINANCE MANAGER. MAKES STATE CHANGES RELATED TO SIGH FINANCE
    bytes32 private constant SIGH = "SIGH";
    bytes32 private constant SIGH_Finance_NFT_BOOSTERS = "SIGH_Finance_NFT_BOOSTERS";
    bytes32 private constant SIGH_SPEED_CONTROLLER = "SIGH_SPEED_CONTROLLER";           
    bytes32 private constant SIGH_VOLATILITY_HARVESTER = "SIGH_VOLATILITY_HARVESTER";         
    bytes32 private constant SIGH_TREASURY = "SIGH_TREASURY";                           
    bytes32 private constant SIGH_STAKING = "SIGH_STAKING";                             

    //Contracts which collect Fee & SIGH Pay
    bytes32 private constant SIGH_Finance_Fee_Collector = "SIGH_Finance_Fee_Collector";
    bytes32 private constant SIGH_Finance_SIGHPAY_AGGREGATOR = "SIGH_Finance_SIGHPAY_AGGREGATOR";

    //Price Oracle and general contracts
    bytes32 private constant PRICE_ORACLE = "PRICE_ORACLE";


// ################################
// ######  CONSTRUCTOR ############
// ################################

    constructor(address SIGHFinanceManagerAddress, address LendingPoolManagerAddress) {
        _setAddress(SIGH_FINANCE_MANAGER, SIGHFinanceManagerAddress);
        _setAddress(LENDING_POOL_MANAGER, LendingPoolManagerAddress);

        emit SIGHFinanceManagerUpdated( getAddress(SIGH_FINANCE_MANAGER) );
        emit LendingPoolManagerUpdated( getAddress(LENDING_POOL_MANAGER) );
    }

// ################################
// #########  MODIFIERS ###########
// ################################

    modifier onlySIGHFinanceManager {
        address sighFinanceManager =  getAddress(SIGH_FINANCE_MANAGER);
        require( sighFinanceManager == msg.sender, "The caller must be the SIGH FINANCE Manager" );
        _;
    }

    modifier onlyLendingPoolManager {
        address LendingPoolManager =  getAddress(LENDING_POOL_MANAGER);
        require( LendingPoolManager == msg.sender, "The caller must be the Lending Protocol Manager" );
        _;
    }

// ########################################################################################
// #########  PROTOCOL MANAGERS ( LendingPool Manager and SighFinance Manager ) ###########
// ########################################################################################

    function getLendingPoolManager() external view override returns (address) {
        return getAddress(LENDING_POOL_MANAGER);
    }

    function getPendingLendingPoolManager() external view override returns (address) {
        return getAddress(PENDING_LENDING_POOL_MANAGER);
    }

    function setPendingLendingPoolManager(address _pendinglendingPoolManager) external override  onlyLendingPoolManager {
        _setAddress(PENDING_LENDING_POOL_MANAGER, _pendinglendingPoolManager);
        emit PendingLendingPoolManagerUpdated(_pendinglendingPoolManager);
    }

    function acceptLendingPoolManager() external override {
        address pendingLendingPoolManager = getAddress(PENDING_LENDING_POOL_MANAGER);
        require(msg.sender == pendingLendingPoolManager, "Only the Pending Lending Pool Manager can call this function to be accepted to become the Lending Pool Manager");
        _setAddress(LENDING_POOL_MANAGER, pendingLendingPoolManager);
        _setAddress(PENDING_LENDING_POOL_MANAGER, address(0));
        emit PendingLendingPoolManagerUpdated( getAddress(PENDING_LENDING_POOL_MANAGER) );
        emit LendingPoolManagerUpdated( getAddress(LENDING_POOL_MANAGER) );
    }

    function getSIGHFinanceManager() external view override returns (address) {
        return getAddress(SIGH_FINANCE_MANAGER);
    }

    function getPendingSIGHFinanceManager() external view override returns (address) {
        return getAddress(PENDING_SIGH_FINANCE_MANAGER);
    }

    function setPendingSIGHFinanceManager(address _PendingSIGHFinanceManager) external override  onlySIGHFinanceManager {
        _setAddress(PENDING_SIGH_FINANCE_MANAGER, _PendingSIGHFinanceManager);
        emit PendingSIGHFinanceManagerUpdated(_PendingSIGHFinanceManager);
    }

    function acceptSIGHFinanceManager() external override {
        address _PendingSIGHFinanceManager = getAddress(PENDING_SIGH_FINANCE_MANAGER);
        require(msg.sender == _PendingSIGHFinanceManager, "Only the Pending SIGH Finance Manager can call this function to be accepted to become the SIGH Finance Manager");
        _setAddress(SIGH_FINANCE_MANAGER, _PendingSIGHFinanceManager);
        _setAddress(PENDING_SIGH_FINANCE_MANAGER, address(0));
        emit PendingSIGHFinanceManagerUpdated( getAddress(PENDING_SIGH_FINANCE_MANAGER) );
        emit SIGHFinanceManagerUpdated( getAddress(SIGH_FINANCE_MANAGER) );
    }


// #########################################################################
// ####___________ LENDING POOL PROTOCOL CONTRACTS _____________############
// ########## 1. LendingPoolConfigurator (Upgradagble) #####################
// ########## 3. LendingPool (Upgradagble) #################################
// ########## 6. FeeProvider (Upgradagble) #################################
// ########## 7. LendingPoolLiqAndLoanManager (Directly Changed) ##########
// ########## 8. LendingRateOracle (Directly Changed) ######################
// #########################################################################


// ############################################
// ######  LendingPoolConfigurator proxy ######
// ############################################

    /**
    * @dev returns the address of the LendingPoolConfigurator proxy
    * @return the lending pool configurator proxy address
    **/
    function getLendingPoolConfigurator() external view override returns (address) {
        return getAddress(LENDING_POOL_CONFIGURATOR);
    }

    /**
    * @dev updates the implementation of the lending pool configurator
    * @param _configurator the new lending pool configurator implementation
    **/
    function setLendingPoolConfiguratorImpl(address _configurator) external override onlyLendingPoolManager {
        updateImplInternal(LENDING_POOL_CONFIGURATOR, _configurator);
        emit LendingPoolConfiguratorUpdated(_configurator);
    }



// ################################
// ######  LendingPool proxy ######
// ################################
    /**
    * @dev returns the address of the LendingPool proxy
    * @return the lending pool proxy address
    **/
    function getLendingPool() external view override returns (address) {
        return getAddress(LENDING_POOL);
    }


    /**
    * @dev updates the implementation of the lending pool
    * @param _pool the new lending pool implementation
    **/
    function setLendingPoolImpl(address _pool) external override onlyLendingPoolManager {
        updateImplInternal(LENDING_POOL, _pool);
        emit LendingPoolUpdated(_pool);
    }
    
    
// ###################################
// ######  getFeeProvider proxy ######
// ###################################
    /**
    * @dev returns the address of the FeeProvider proxy
    * @return the address of the Fee provider proxy
    **/
    function getFeeProvider() external view override returns (address) {
        return getAddress(FEE_PROVIDER);
    }

    /**
    * @dev updates the implementation of the FeeProvider proxy
    * @param _feeProvider the new lending pool fee provider implementation
    **/
    function setFeeProviderImpl(address _feeProvider) external override onlyLendingPoolManager {
        updateImplInternal(FEE_PROVIDER, _feeProvider);
        emit FeeProviderUpdated(_feeProvider);
    }

// ##################################################
// ######  LendingPoolLiqAndLoanManager ######
// ##################################################
    /**
    * @dev returns the address of the LendingPoolLiqAndLoanManager. Since the manager is used
    * through delegateCall within the LendingPool contract, the proxy contract pattern does not work properly hence
    * the addresses are changed directly.
    * @return the address of the Lending pool LiqAndLoan manager
    **/

    function getLendingPoolLiqAndLoanManager() external view override returns (address) {
        return getAddress(LENDING_POOL_LIQANDLOAN_MANAGER);
    }

    /**
    * @dev updates the address of the Lending pool LiqAndLoan manager
    * @param _manager the new lending pool LiqAndLoan manager address
    **/
    function setLendingPoolLiqAndLoanManager(address _manager) external override onlyLendingPoolManager {
        _setAddress(LENDING_POOL_LIQANDLOAN_MANAGER, _manager);
        emit LendingPoolLiqAndLoanManagerUpdated(_manager);
    }

// ##################################################
// ######  LendingRateOracle ##################
// ##################################################

    function getLendingRateOracle() external view override returns (address) {
        return getAddress(LENDING_RATE_ORACLE);
    }

    function setLendingRateOracle(address _lendingRateOracle) external override onlyLendingPoolManager {
        _setAddress(LENDING_RATE_ORACLE, _lendingRateOracle);
        emit LendingRateOracleUpdated(_lendingRateOracle);
    }


// ####################################################################################
// ####___________ SIGH FINANCE RELATED CONTRACTS _____________########################
// ########## 1. SIGH (Initialized only once) #########################################
// ########## 1. SIGH NFT BOOSTERS (Initialized only once) ############################
// ########## 2. SIGHFinanceConfigurator (Upgradable) #################################
// ########## 2. SIGH Speed Controller (Initialized only once) ########################
// ########## 3. SIGHTreasury (Upgradagble) ###########################################
// ########## 4. SIGHVolatilityHarvester (Upgradagble) ###################################
// ########## 5. SIGHStaking (Upgradagble) ###################################
// ####################################################################################

// ################################                                                     
// ######  SIGH ADDRESS ###########                                                     
// ################################                                                     

    function getSIGHAddress() external view override returns (address) {
        return getAddress(SIGH);
    }

    function setSIGHAddress(address sighAddress) external override onlySIGHFinanceManager {
        // require (!isSighInitialized, "SIGH Instrument address can only be initialized once.");
        isSighInitialized  = true;
        // updateImplInternal(SIGH, sighAddress);
        _setAddress(SIGH, sighAddress);
        emit SIGHAddressUpdated(sighAddress);
    }

// #####################################
// ######  SIGH NFT BOOSTERS ###########
// #####################################

    // SIGH FINANCE NFT BOOSTERS - Provide Discount on Deposit & Borrow Fee
    function getSIGHNFTBoosters() external view override returns (address) {
        return getAddress(SIGH_Finance_NFT_BOOSTERS);
    }

    function setSIGHNFTBoosters(address _SIGHNFTBooster) external override onlySIGHFinanceManager {
        // require (!isNFTBoosterInitialized, "SIGH NFT Boosters address can only be initialized once.");
//        isNFTBoosterInitialized  = true;
        _setAddress(SIGH_Finance_NFT_BOOSTERS, _SIGHNFTBooster);
        emit SIGHNFTBoosterUpdated(_SIGHNFTBooster);
    }

// ############################################
// ######  SIGHFinanceConfigurator proxy ######
// ############################################

    /**
    * @dev returns the address of the SIGHFinanceConfigurator proxy
    * @return the SIGH Finance configurator proxy address
    **/
    function getSIGHFinanceConfigurator() external view override returns (address) {
        return getAddress(SIGH_FINANCE_CONFIGURATOR);
    }

    /**
    * @dev updates the implementation of the lending pool configurator
    * @param _configurator the new lending pool configurator implementation
    **/
    function setSIGHFinanceConfiguratorImpl(address _configurator) external override onlySIGHFinanceManager {
        updateImplInternal(SIGH_FINANCE_CONFIGURATOR, _configurator);
        emit SIGHFinanceConfiguratorUpdated(_configurator);
    }

// ############################################
// ######  SIGH Speed Controller ########
// ############################################

    /**
    * @dev returns the address of the SIGH_SPEED_CONTROLLER proxy
    * @return the SIGH Speed Controller address
    **/
    function getSIGHSpeedController() external view override returns (address) {
        return getAddress(SIGH_SPEED_CONTROLLER);
    }

    /**
    * @dev sets the address of the SIGH Speed Controller
    * @param _SIGHSpeedController the SIGH Speed Controller implementation
    **/
    function setSIGHSpeedController(address _SIGHSpeedController) external override onlySIGHFinanceManager {
        // require (!isSighSpeedControllerInitialized, "SIGH Speed Controller address can only be initialized once.");
        // isSighSpeedControllerInitialized  = true;
        updateImplInternal(SIGH_SPEED_CONTROLLER, _SIGHSpeedController);
        emit SIGHSpeedControllerUpdated(_SIGHSpeedController);
    }



// #################################  ADDED BY SIGH FINANCE
// ######  SIGHTreasury proxy ######  ADDED BY SIGH FINANCE
// #################################  ADDED BY SIGH FINANCE

    function getSIGHTreasury() external view override returns (address) {
        return getAddress(SIGH_TREASURY);
    }

    /**
    * @dev updates the address of the SIGH Treasury Contract
    * @param _SIGHTreasury the new SIGH Treasury Contract address
    **/
    function setSIGHTreasuryImpl(address _SIGHTreasury) external override onlySIGHFinanceManager {
        updateImplInternal(SIGH_TREASURY, _SIGHTreasury);
        emit SIGHTreasuryImplUpdated(_SIGHTreasury);
    }

// #############################################  ADDED BY SIGH FINANCE
// ######  SIGHVolatilityHarvester proxy #######     ADDED BY SIGH FINANCE
// #############################################  ADDED BY SIGH FINANCE

    function getSIGHVolatilityHarvester() external view override returns (address) {
        return getAddress(SIGH_VOLATILITY_HARVESTER);
    }

    /**
    * @dev updates the address of the SIGH Distribution Handler Contract (Manages the SIGH Speeds)
    * @param _SIGHVolatilityHarvester the new SIGH Distribution Handler (Impl) Address
    **/
    function setSIGHVolatilityHarvesterImpl(address _SIGHVolatilityHarvester) external override onlySIGHFinanceManager  {
        updateImplInternal(SIGH_VOLATILITY_HARVESTER, _SIGHVolatilityHarvester);
        emit SIGHVolatilityHarvesterImplUpdated(_SIGHVolatilityHarvester);
    }

// #############################################  ADDED BY SIGH FINANCE
// ######  SIGHStaking proxy ###################  ADDED BY SIGH FINANCE
// #############################################  ADDED BY SIGH FINANCE

    function getSIGHStaking() external view override returns (address) {
        return getAddress(SIGH_STAKING);
    }

    /**
    * @dev updates the address of the SIGH Distribution Handler Contract (Manages the SIGH Speeds)
    * @param _SIGHStaking the new lending pool LiqAndLoan manager address
    **/
    function setSIGHStaking(address _SIGHStaking) external override onlySIGHFinanceManager  {
        updateImplInternal(SIGH_STAKING, _SIGHStaking);
        emit SIGHStakingImplUpdated(_SIGHStaking);
    }

// #############################################
// ######  SIGH PAY AGGREGATOR #################
// #############################################

    // SIGH FINANCE : SIGH PAY AGGREGATOR - Collects SIGH PAY Payments
    function getSIGHPAYAggregator() external view override returns (address) {
        return getAddress(SIGH_Finance_SIGHPAY_AGGREGATOR);
    }

    function setSIGHPAYAggregator(address _SIGHPAYAggregator) external override onlySIGHFinanceManager {
        updateImplInternal(SIGH_Finance_SIGHPAY_AGGREGATOR, _SIGHPAYAggregator);
        emit SIGHFinanceSIGHPAYAggregatorUpdated(_SIGHPAYAggregator);
    }

// ####################################################
// ######  SIGH FINANCE FEE COLLECTOR #################
// ###################################################

    // SIGH FINANCE FEE COLLECTOR - BORROWING / FLASH LOAN FEE TRANSFERRED TO THIS ADDRESS
    function getSIGHFinanceFeeCollector() external view override returns (address) {
        return getAddress(SIGH_Finance_Fee_Collector);
    }

    function setSIGHFinanceFeeCollector(address _feeCollector) external override onlySIGHFinanceManager {
        _setAddress(SIGH_Finance_Fee_Collector, _feeCollector);
        emit SIGHFinanceFeeCollectorUpdated(_feeCollector);
    }

// ###################################################################################
// ######  THESE CONTRACTS ARE NOT USING PROXY SO ADDRESS ARE DIRECTLY UPDATED #######
// ###################################################################################

    /**
    * @dev the functions below are storing specific addresses that are outside the context of the protocol
    * hence the upgradable proxy pattern is not used
    **/
    function getPriceOracle() external view override returns (address) {
        return getAddress(PRICE_ORACLE);
    }

    function setPriceOracle(address _priceOracle) external override onlyLendingPoolManager {
        _setAddress(PRICE_ORACLE, _priceOracle);
        emit PriceOracleUpdated(_priceOracle);
    }


// #############################################
// ######  FUNCTION TO UPGRADE THE PROXY #######
// #############################################

    /**
    * @dev internal function to update the implementation of a specific component of the protocol
    * @param _id the id of the contract to be updated
    * @param _newAddress the address of the new implementation
    **/
    function updateImplInternal(bytes32 _id, address _newAddress) internal {
        address payable proxyAddress = address(uint160(getAddress(_id)));

        InitializableAdminUpgradeabilityProxy proxy = InitializableAdminUpgradeabilityProxy(proxyAddress);
        bytes memory params = abi.encodeWithSignature("initialize(address)", address(this));            // initialize function is called in the new implementation contract

        if (proxyAddress == address(0)) {
            proxy = new InitializableAdminUpgradeabilityProxy();
            proxy.initialize(_newAddress, address(this), params);
            _setAddress(_id, address(proxy));
            emit ProxyCreated(_id, address(proxy));
        } else {
            proxy.upgradeToAndCall(_newAddress, params);
        }
    }
}
