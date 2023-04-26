  
// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

/**
* @title FeeProvider contract Interface
* @notice Implements calculation for the fees applied by the protocol based on the Boosters
* @author SIGH Finance (_astromartian)
**/
interface IFeeProvider  {

    event depositFeePercentUpdated(uint _depositFeePercent);
    event borrowFeePercentUpdated(uint totalBorrowFeePercent_);
    event flashLoanFeePercentUpdated(uint totalFlashLoanFeePercent_);
    event platformFeePercentUpdated(uint _platformFeePercent);

    event initalFuelForABoosterCategoryUpdated(string categoryName,uint initialFuel);
    event topUpOptionUpdated(string category, uint optionNo,uint _fee, uint _multiplier);
    event tokenForPaymentUpdated(address prevToken,address tokenAccepted);
    event tokensTransferred(address token, address destination, uint amount,uint newBalance );

    event _boosterTopUp( uint boosterID,uint optionNo,uint amount,uint topUp,uint totalFuelRemaining);


// ###############################
// ###### PROXY RELATED ##########
// ###############################

    function refreshConfiguration() external returns (bool);

// ###############################################################################################
// ###### EXTERNAL FUNCTIONS TO CALCULATE THE FEE (Can only be called by LendingPool) ############
// ###### 1. calculateDepositFee() ##########
// ###### 2. calculateFlashLoanFee() #######################################
// ###### 1. calculateBorrowFee() ##########
// ################################################################################################

    function calculateDepositFee(address _user,address instrument, uint256 _amount, uint boosterId) external returns (uint256 ,uint256 ,uint256 );
    function calculateBorrowFee(address _user, address instrument, uint256 _amount, uint boosterId) external returns (uint256 platformFee, uint256 reserveFee) ;
    function calculateFlashLoanFee(address _user, uint256 _amount, uint boosterId) external view returns (uint256 ,uint256 ,uint256 ) ;


// #################################
// ####### FUNCTIONS TO INCREASE FUEL LIMIT  ########
// #################################

    function fuelTopUp(uint optionNo, uint boosterID) external ;


// #################################
// ####### ADMIN FUNCTIONS  ########
// #################################

    function updateTotalDepositFeePercent(uint _depositFeePercent) external returns (bool) ;
    function updateTotalBorrowFeePercent(uint totalBorrowFeePercent_) external returns (bool) ;
    function updateTotalFlashLoanFeePercent(uint totalFlashLoanFeePercent_ ) external returns (bool) ;
    function updatePlatformFeePercent(uint _platformFeePercent) external returns (bool);

    function UpdateABoosterCategoryFuelAmount(string calldata categoryName, uint initialFuel ) external returns (bool);
    function updateATopUpOption(string calldata category, uint optionNo, uint _fee, uint _multiplier) external returns (bool) ;

    function updateTokenAccepted(address _token) external  returns (bool) ;
    function transferFunds(address token, address destination, uint amount) external returns (bool) ;

// ###############################
// ####### EXTERNAL VIEW  ########
// ###############################

    function getBorrowFeePercentage() external view returns (uint256) ;
    function getDepositFeePercentage() external view returns (uint256) ;
    function getFlashLoanFeePercentage() external view returns (uint256) ;

    function getFuelAvailable(uint boosterID) external view returns (uint256) ;
    function getFuelUsed(uint boosterID) external view returns (uint256) ;
    function getOptionDetails(string calldata category, uint optionNo) external view returns (uint fee, uint multiplier) ;

}