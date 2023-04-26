  
// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {VersionedInitializable} from "../dependencies/upgradability/VersionedInitializable.sol";
import {IERC20} from "../dependencies/openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Detailed} from "../dependencies/openzeppelin/token/ERC20/IERC20Detailed.sol";
import {PercentageMath} from "./libraries/math/PercentageMath.sol";
import {Exponential} from "./libraries/math/Exponential.sol";

import {IGlobalAddressesProvider} from "../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";
import {ISIGHBoosters} from "../../interfaces/NFTBoosters/ISIGHBoosters.sol";
import {IFeeProvider} from "../../interfaces/lendingProtocol/IFeeProvider.sol";
import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
import {SafeMath} from "../dependencies/openzeppelin/math/SafeMath.sol";
import "../dependencies/openzeppelin/token/ERC20/IERC20Detailed.sol";


/**
* @title FeeProvider contract
* @notice Implements calculation for the fees applied by the protocol
* @author Aave, SIGH Finance
**/
contract FeeProvider is IFeeProvider, VersionedInitializable {

    using PercentageMath for uint256;
    using SafeMath for uint256;

    IGlobalAddressesProvider private globalAddressesProvider;
    IPriceOracleGetter private priceOracle ;
    ISIGHBoosters private SIGH_Boosters;

    uint256 public totalFlashLoanFeePercent;        // Flash Loan Fee 
    uint256 public totalBorrowFeePercent;           // Borrow Fee
    uint256 public totalDepositFeePercent;          // Deposit Fee
    uint256 public platformFeePercent;              // Platform Fee (% of the Borrow Fee / Deposit Fee)

    address private tokenAccepted; 

    mapping (string => uint) initialFuelAmount;  // Initial Fuel the boosters of a particular category have


    struct optionType{
        uint256 fee;                // Fee Charged for this option
        uint256 multiplier;         // Fuel multiplier (fuel top up = fee * multiplier). It is adjusted by 2 decimal places.
                                    // Eq, multiplier = 120, means fuelTopUp = fee * 120/100 = 1.2 * Fee
    }

    mapping (string => mapping (uint => optionType) ) private fuelTopUpOptions; // BoosterType => ( optionNo => optionType )

    struct booster{
        bool initiated;                // To check if this booster has ever been used or not
        uint256 totalFuelRemaining;     // Current Amount of fuel available
        uint256 totalFuelUsed;          // Total Fuel used
    }

    mapping (uint256 => booster) private boosterFuelInfo;    // boosterID => Fuel Remaining (Remaining Volume on which discount will be given) Mapping


    //only SIGH Distribution Manager can use functions affected by this modifier
    modifier onlySighFinanceConfigurator {
        require(globalAddressesProvider.getSIGHFinanceConfigurator() == msg.sender, "The caller must be the SIGH Finance Configurator");
        _;
    }

    //only LendingPool contract can call these functions
    modifier onlyLendingPool {
        require(globalAddressesProvider.getLendingPool() == msg.sender, "The caller must be the Lending Pool Contract");
        _;
    }

// ###############################
// ###### PROXY RELATED ##########
// ###############################

    uint256 constant public FEE_PROVIDER_REVISION = 0x1;

    function getRevision() internal pure override returns(uint256) {
        return FEE_PROVIDER_REVISION;
    }
    /**
    * @dev initializes the FeeProvider after it's added to the proxy
    * @param _addressesProvider the address of the GlobalAddressesProvider
    */
    function initialize(address _addressesProvider) public initializer {
        globalAddressesProvider = IGlobalAddressesProvider(_addressesProvider);
        totalDepositFeePercent = 50;            // deposit fee = 0.5%
        totalFlashLoanFeePercent = 5;           // Flash loan fee = 0.05%
        totalBorrowFeePercent =  50;            // borrow fee = 0.5%
        platformFeePercent = 5000;              // = 50% of total Fee
    }

    function refreshConfiguration() external override onlySighFinanceConfigurator returns (bool) {
        priceOracle = IPriceOracleGetter(globalAddressesProvider.getPriceOracle());
        SIGH_Boosters = ISIGHBoosters(globalAddressesProvider.getSIGHNFTBoosters());
        return true;
    }

// ############################################################################################################################
// ###### EXTERNAL FUNCTIONS TO CALCULATE THE FEE #############################################################################################
// ###### 1. calculateDepositFee() ##########
// ###### 2. calculateFlashLoanFee() #######################################
// ###### 1. calculateBorrowFee() ##########
// ############################################################################################################################

    function calculateDepositFee(address _user,address instrument, uint256 _amount, uint boosterId) external override onlyLendingPool returns (uint256 ,uint256 ,uint256 ) {

        uint totalFee = _amount.percentMul(totalDepositFeePercent);       // totalDepositFeePercent = 50 represents 0.5%
        uint platformFee = totalFee.percentMul(platformFeePercent);       // platformFeePercent = 5000 represents 50%
        uint sighPay = totalFee.sub(platformFee);

        if (boosterId == 0) {
            return (totalFee,platformFee,sighPay);
        }

        require( _user == SIGH_Boosters.ownerOfBooster(boosterId), "Deposit() caller doesn't have the mentioned SIGH Booster needed to claim the discount. Please check the BoosterID that you provided again." );

        if ( !boosterFuelInfo[boosterId].initiated ) {
            string memory category = SIGH_Boosters.getBoosterCategory(boosterId);
            boosterFuelInfo[boosterId].totalFuelRemaining = initialFuelAmount[category];
            boosterFuelInfo[boosterId].initiated = true;
        }

        if ( boosterFuelInfo[boosterId].totalFuelRemaining > 0 ) {
            uint priceUSD = priceOracle.getAssetPrice(instrument);
            uint priceDecimals = priceOracle.getAssetPriceDecimals(instrument);
            require(priceUSD > 0, "Oracle returned invalid price");

            uint value = totalFee.mul(priceUSD * 10**8);              // Adjusted by 8 decimals
            value = value.div(10**priceDecimals);                     // Corrected by Price Decimals

            boosterFuelInfo[boosterId].totalFuelRemaining = boosterFuelInfo[boosterId].totalFuelRemaining >= value ? boosterFuelInfo[boosterId].totalFuelRemaining.sub(value) : 0 ;
            boosterFuelInfo[boosterId].totalFuelUsed = boosterFuelInfo[boosterId].totalFuelUsed.add(value);
            return (0,0,0);
        }

        (uint platformFeeDiscount, uint sighPayDiscount) = SIGH_Boosters.getDiscountRatiosForBooster(boosterId);
        platformFee = platformFee.sub( platformFee.div(platformFeeDiscount) ) ;
        sighPay = sighPay.sub( sighPay.div(sighPayDiscount) ) ;
        totalFee = platformFee.add(sighPay);

        return (totalFee, platformFee,sighPay) ;
    }


    function calculateFlashLoanFee(address _user, uint256 _amount, uint boosterId) external view override returns (uint256 ,uint256 ,uint256) {
        uint totalFee = _amount.percentMul(totalFlashLoanFeePercent);       // totalFlashLoanFeePercent = 5 represents 0.05%
        uint platformFee = totalFee.percentMul(platformFeePercent);       // platformFeePercent = 5000 represents 50%
        uint sighPay = totalFee.sub(platformFee);

        if (boosterId == 0) {
            return (totalFee,platformFee,sighPay);
        }

        require( _user == SIGH_Boosters.ownerOfBooster(boosterId), "FlashLoan() caller doesn't have the mentioned SIGH Booster needed to claim the discount on Fee. Please check the BoosterID that you provided again." );

        (uint platformFeeDiscount, uint sighPayDiscount) = SIGH_Boosters.getDiscountRatiosForBooster(boosterId);
        platformFee = platformFee.sub( platformFee.div(platformFeeDiscount) ) ;
        sighPay = sighPay.sub( sighPay.div(sighPayDiscount) ) ;
        totalFee = platformFee.add(sighPay);
        
        return (totalFee,platformFee,sighPay);
    }
    
    

    function calculateBorrowFee(address _user, address instrument, uint256 _amount, uint boosterId) external override onlyLendingPool returns (uint256, uint256) {
        uint totalFee = _amount.percentMul(totalBorrowFeePercent);       // totalDepositFeePercent = 50 represents 0.5%
        uint256 platformFee = totalFee.percentMul(platformFeePercent);       // platformFeePercent = 5000 represents 50%
        uint256 reserveFee = totalFee.sub(platformFee);

        if (boosterId == 0) {
            return (platformFee,reserveFee);
        }

        require( _user == SIGH_Boosters.ownerOfBooster(boosterId), "User against which borrow is being initiated doesn't have the mentioned SIGH Booster needed to claim the discount. Please check the BoosterID that you provided again." );

        if ( !boosterFuelInfo[boosterId].initiated ) {
            string memory category = SIGH_Boosters.getBoosterCategory(boosterId);
            boosterFuelInfo[boosterId].totalFuelRemaining = initialFuelAmount[category];
            boosterFuelInfo[boosterId].initiated = true;
        }

        if (  boosterFuelInfo[boosterId].totalFuelRemaining > 0 ) {
            uint priceUSD = priceOracle.getAssetPrice(instrument);
            uint priceDecimals = priceOracle.getAssetPriceDecimals(instrument);
            require(priceUSD > 0, "Oracle returned invalid price");

            uint value = totalFee.mul(priceUSD * 10**8);              // Adjusted by 8 decimals
            value = value.div(10**priceDecimals);                     // Corrected by Price Decimals

            boosterFuelInfo[boosterId].totalFuelRemaining =  boosterFuelInfo[boosterId].totalFuelRemaining >= value ?  boosterFuelInfo[boosterId].totalFuelRemaining.sub(value) : 0 ;
            boosterFuelInfo[boosterId].totalFuelUsed = boosterFuelInfo[boosterId].totalFuelUsed.add(value);
            return (0,0);
        }

        (uint platformFeeDiscount, uint reserveFeeDiscount) = SIGH_Boosters.getDiscountRatiosForBooster(boosterId);
        platformFee = platformFee.sub( platformFee.div(platformFeeDiscount) ) ;
        reserveFee = reserveFee.sub( reserveFee.div(reserveFeeDiscount) ) ;

        return (platformFee,reserveFee) ;
    }

// #################################
// ####### FUNCTIONS TO INCREASE FUEL LIMIT  ########
// #################################

    function fuelTopUp(uint optionNo, uint boosterID) override external {
        require( SIGH_Boosters.isValidBooster(boosterID) , "Not a Valid Booster" );
        string memory category = SIGH_Boosters.getBoosterCategory(boosterID);

        optionType memory selectedOption = fuelTopUpOptions[category][optionNo];
        uint amount = selectedOption.fee;
        require(amount > 0,"Option selected not valid");

        uint8 decimals = IERC20Detailed(tokenAccepted).decimals();
        amount = amount.mul(10**decimals);

        uint256 prevBalance = IERC20(tokenAccepted).balanceOf(address(this));
        IERC20(tokenAccepted).transferFrom(msg.sender,address(this),amount);
        uint256 newBalance = IERC20(tokenAccepted).balanceOf(address(this));
        require( newBalance == prevBalance.add(amount),"ERC20 transfer failure");

        uint _multiplier = selectedOption.multiplier;
        uint topUp = amount.mul(_multiplier);
        topUp = topUp.div(100);                    // topUp = fee * multiplier, where multipler = 120 represents 1.2
        
        boosterFuelInfo[boosterID].totalFuelRemaining = boosterFuelInfo[boosterID].totalFuelRemaining.add(topUp);
        emit _boosterTopUp( boosterID, optionNo, amount, topUp, boosterFuelInfo[boosterID].totalFuelRemaining);
    }



// #################################
// ####### ADMIN FUNCTIONS  ########
// #################################

    function updateTotalDepositFeePercent(uint _depositFeePercent) external override onlySighFinanceConfigurator returns (bool) {
        totalDepositFeePercent = _depositFeePercent;
        emit depositFeePercentUpdated(_depositFeePercent);
        return true;
    }

    function updateTotalBorrowFeePercent(uint totalBorrowFeePercent_) external override onlySighFinanceConfigurator returns (bool) {
        totalBorrowFeePercent = totalBorrowFeePercent_;
        emit borrowFeePercentUpdated(totalBorrowFeePercent_);
        return true;
    }

    function updateTotalFlashLoanFeePercent(uint totalFlashLoanFeePercent_ ) external override onlySighFinanceConfigurator returns (bool) {
        totalFlashLoanFeePercent = totalFlashLoanFeePercent_;
        emit flashLoanFeePercentUpdated(totalFlashLoanFeePercent_);
        return true;
    }

    function updatePlatformFeePercent(uint _platformFeePercent) external override onlySighFinanceConfigurator returns (bool) {
        platformFeePercent = _platformFeePercent;
        emit platformFeePercentUpdated(_platformFeePercent);
        return true;
    }

    function UpdateABoosterCategoryFuelAmount(string memory categoryName, uint initialFuel ) external override onlySighFinanceConfigurator returns (bool) {
        require(initialFuel > 0, 'Initial Fuel cannot be 0'); 
        require(SIGH_Boosters.isCategorySupported(categoryName),'Category not present');
        initialFuelAmount[categoryName] = initialFuel;

        emit initalFuelForABoosterCategoryUpdated(categoryName,initialFuel);
        return true;
    }

    function updateATopUpOption(string memory category, uint optionNo, uint _fee, uint _multiplier) external override onlySighFinanceConfigurator returns (bool) {
        optionType memory newType = optionType({ fee: _fee, multiplier: _multiplier  });
        fuelTopUpOptions[category][optionNo] = newType;
        emit topUpOptionUpdated(category, optionNo, _fee, _multiplier);
        return true;
    }

    function updateTokenAccepted(address _token) external override onlySighFinanceConfigurator returns (bool) {
        require(_token != address(0),'Not a valid address');
        address prevToken = tokenAccepted;
        tokenAccepted = _token;
        emit tokenForPaymentUpdated(prevToken, tokenAccepted);
        return true;
    }

    function transferFunds(address token, address destination, uint amount) external override onlySighFinanceConfigurator returns (bool) {
        require(token != address(0),'Not a valid token address');
        require(destination != address(0),'Not a valid  destination address');
        require(amount > 0,'Amount needs to be greater than 0');

        uint256 prevBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(destination,amount);
        uint256 newBalance = IERC20(token).balanceOf(address(this));
        require( newBalance == prevBalance.sub(amount),"ERC20 transfer failure");

        emit tokensTransferred(token, destination, amount, newBalance );
        return true;
    }

// ###############################
// ####### EXTERNAL VIEW  ########
// ###############################

    function getBorrowFeePercentage() external view override returns (uint256) {
        return totalBorrowFeePercent;
    }

    function getDepositFeePercentage() external view override returns (uint256) {
        return totalDepositFeePercent;
    }

    function getFlashLoanFeePercentage() external view override returns (uint256) {
        return totalFlashLoanFeePercent;
    }

    function getFuelAvailable(uint boosterID) external view override returns (uint256) {
        return boosterFuelInfo[boosterID].totalFuelRemaining;
    }

    function getFuelUsed(uint boosterID) external view override returns (uint256) {
        return  boosterFuelInfo[boosterID].totalFuelUsed;
    }

    function getOptionDetails(string memory category, uint optionNo) external view override returns (uint fee, uint multiplier) {
        return (fuelTopUpOptions[category][optionNo].fee, fuelTopUpOptions[category][optionNo].multiplier);
    }

}