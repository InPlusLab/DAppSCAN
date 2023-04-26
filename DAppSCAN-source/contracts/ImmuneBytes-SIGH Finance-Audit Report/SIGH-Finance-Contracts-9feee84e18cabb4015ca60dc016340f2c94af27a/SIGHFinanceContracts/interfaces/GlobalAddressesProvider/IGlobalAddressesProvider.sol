// SPDX-License-Identifier: agpl-3.0

pragma solidity ^0.7.0;

/**
@title GlobalAddressesProvider interface
@notice provides the interface to fetch the LendingPoolCore address
 */

interface IGlobalAddressesProvider  {

// ########################################################################################
// #########  PROTOCOL MANAGERS ( LendingPool Manager and SighFinance Manager ) ###########
// ########################################################################################

    function getLendingPoolManager() external view returns (address);
    function getPendingLendingPoolManager() external view returns (address);

    function setPendingLendingPoolManager(address _pendinglendingPoolManager) external;
    function acceptLendingPoolManager() external;

    function getSIGHFinanceManager() external view returns (address);
    function getPendingSIGHFinanceManager() external view returns (address);

    function setPendingSIGHFinanceManager(address _PendingSIGHFinanceManager) external;
    function acceptSIGHFinanceManager() external;

// #########################################################################
// ####___________ LENDING POOL PROTOCOL CONTRACTS _____________############
// ########## 1. LendingPoolConfigurator (Upgradagble) #####################
// ########## 2. LendingPoolCore (Upgradagble) #############################
// ########## 3. LendingPool (Upgradagble) #################################
// ########## 4. LendingPoolDataProvider (Upgradagble) #####################
// ########## 5. LendingPoolParametersProvider (Upgradagble) ###############
// ########## 6. FeeProvider (Upgradagble) #################################
// ########## 7. LendingPoolLiqAndLoanManager (Directly Changed) ##########
// ########## 8. LendingRateOracle (Directly Changed) ######################
// #########################################################################

    function getLendingPoolConfigurator() external view returns (address);
    function setLendingPoolConfiguratorImpl(address _configurator) external;

    function getLendingPool() external view returns (address);
    function setLendingPoolImpl(address _pool) external;

    function getFeeProvider() external view returns (address);
    function setFeeProviderImpl(address _feeProvider) external;

    function getLendingPoolLiqAndLoanManager() external view returns (address);
    function setLendingPoolLiqAndLoanManager(address _manager) external;

    function getLendingRateOracle() external view returns (address);
    function setLendingRateOracle(address _lendingRateOracle) external;

// ####################################################################################
// ####___________ SIGH FINANCE RELATED CONTRACTS _____________########################
// ########## 1. SIGH (Initialized only once) #########################################
// ########## 2. SIGH Finance Configurator (Upgradagble) ################################
// ########## 2. SIGH Speed Controller (Initialized only once) ########################
// ########## 3. SIGH Treasury (Upgradagble) ###########################################
// ########## 4. SIGH Mechanism Handler (Upgradagble) ###################################
// ########## 5. SIGH Staking (Upgradagble) ###################################
// ####################################################################################

    function getSIGHAddress() external view returns (address);
    function setSIGHAddress(address sighAddress) external;

    function getSIGHNFTBoosters() external view returns (address) ;
    function setSIGHNFTBoosters(address _SIGHNFTBooster) external ;

    function getSIGHFinanceConfigurator() external view returns (address);
    function setSIGHFinanceConfiguratorImpl(address sighAddress) external;

    function getSIGHSpeedController() external view returns (address);
    function setSIGHSpeedController(address _SIGHSpeedController) external;

    function getSIGHTreasury() external view returns (address);                                 //  ADDED FOR SIGH FINANCE
    function setSIGHTreasuryImpl(address _SIGHTreasury) external;                                   //  ADDED FOR SIGH FINANCE

    function getSIGHVolatilityHarvester() external view returns (address);                      //  ADDED FOR SIGH FINANCE
    function setSIGHVolatilityHarvesterImpl(address _SIGHVolatilityHarvester) external;             //  ADDED FOR SIGH FINANCE

    function getSIGHStaking() external view returns (address);                      //  ADDED FOR SIGH FINANCE
    function setSIGHStaking(address _SIGHVolatilityHarvester) external;             //  ADDED FOR SIGH FINANCE

// #######################################################
// ####___________ PRICE ORACLE CONTRACT _____________####
// ####_____ SIGH FINANCE FEE COLLECTOR : ADDRESS ____####
// ####_____   SIGH PAYCOLLECTOR : ADDRESS        ____####
// #######################################################

    function getPriceOracle() external view returns (address);
    function setPriceOracle(address _priceOracle) external;


    // SIGH FINANCE FEE COLLECTOR - DEPOSIT / BORROWING / FLASH LOAN FEE TRANSERRED TO THIS ADDRESS
    function getSIGHFinanceFeeCollector() external view returns (address) ;
    function setSIGHFinanceFeeCollector(address _feeCollector) external ;

    function getSIGHPAYAggregator() external view returns (address);                      //  ADDED FOR SIGH FINANCE
    function setSIGHPAYAggregator(address _SIGHPAYAggregator) external;             //  ADDED FOR SIGH FINANCE

}