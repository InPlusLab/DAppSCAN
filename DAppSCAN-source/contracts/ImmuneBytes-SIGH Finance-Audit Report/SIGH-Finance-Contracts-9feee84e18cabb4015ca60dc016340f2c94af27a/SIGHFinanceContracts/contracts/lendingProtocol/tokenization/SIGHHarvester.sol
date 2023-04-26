// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {VersionedInitializable} from "../../dependencies/upgradability/VersionedInitializable.sol";
import {SafeMath} from "../../dependencies/openzeppelin/math/SafeMath.sol";
import {IStableDebtToken} from "../../../interfaces/lendingProtocol/IStableDebtToken.sol";
import {IVariableDebtToken} from "../../../interfaces/lendingProtocol/IVariableDebtToken.sol";
import {IIToken} from "../../../interfaces/lendingProtocol/IIToken.sol";
import {IGlobalAddressesProvider} from "../../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";
import {ISIGHVolatilityHarvester} from "../../../interfaces/SIGHContracts/ISIGHVolatilityHarvester.sol";
import {ILendingPool} from "../../../interfaces/lendingProtocol/ILendingPool.sol";
import {ISIGHHarvester} from "../../../interfaces/lendingProtocol/ISIGHHarvester.sol";


/**
 * @title  $SIGH STREAMS
 * @dev Implementation of the $SIGH Liquidity & Borrowing Streams for ITokens.
 * @author _astromartian
 */
contract SIGHHarvester is ISIGHHarvester, VersionedInitializable {

    using SafeMath for uint256;
    uint private sighInitialIndex = 1e36;        // INDEX (SIGH RELATED)

    address public underlyingInstrumentAddress;
    IIToken public iToken;
    IStableDebtToken public stableDebtToken;
    IVariableDebtToken public variableDebtToken;

    IGlobalAddressesProvider private globalAddressesProvider;           // Only used in Constructor()
    ISIGHVolatilityHarvester public sighVolatilityHarvesterContract;    // Fetches Instrument Indexes/ Calls Function to transfer accured SIGH
    ILendingPool private lendingPool;                                   // Fetches user borrow Balances

    struct Double {
        uint mantissa;
    }

    struct Exp {
        uint mantissa;
    }

    // $SIGH PARAMETERS
    // EACH USER HAS 2 $SIGH STREAMS :-
    // 1. $SIGH STREAM BASED ON VOLATILITY OF THE LIQUIDITY PROVIDED
    // 1. $SIGH STREAM BASED ON VOLATILITY OF THE BORROWED AMOUNT

    uint public sigh_Transfer_Threshold = 1e19;                         // SIGH Transferred when accured >= 1 SIGH 
    mapping (address => uint256) private AccuredSighBalance;           // SIGH Collected 
    mapping (address => uint256) private platformFee;                 // BorrowPlatformFee
    mapping (address => uint256) private reserveFee;                 // BorrowPlatformFee

    struct user_SIGH_State {
        uint256 liquidityStreamIndex;                     // SupplierIndex
        uint256 borrowingStreamIndex;                     // BorrowerIndex
    }
    
    mapping (address => user_SIGH_State) private user_SIGH_States;              


    event SighAccured(address instrument, address user, bool isLiquidityStream, uint recentSIGHAccured  , uint AccuredSighBalance );

    modifier onlyITokenContract {
        require( msg.sender == address(iToken), "The caller of this function must be the associated IToken Contract");
        _;
    }

    modifier onlyDebtTokens {
        require( msg.sender == address(stableDebtToken) || msg.sender ==  address(variableDebtToken), "The caller of this function can only be the associated Debt tokens");
        _;
    }

    modifier onlyOverlyingTokens {
        require( msg.sender == address(iToken) || msg.sender == address(stableDebtToken) || msg.sender ==  address(variableDebtToken), "The caller of this function can only be one of the associated tokens");
        _;
    }

// ########################################
// ####### PROXY RELATED ##################
// ########################################

    uint256 public constant CONFIGURATOR_REVISION = 0x1;

    function getRevision() internal pure override returns (uint256) {
        return CONFIGURATOR_REVISION;
    }

    function initialize(address _globalAddressesProvider, address _underlyingAsset, address _iTokenAddress, address _stableDebtTokenAddress, address _variableDebtTokenTokenAddress) public initializer {
        globalAddressesProvider = IGlobalAddressesProvider(_globalAddressesProvider);
        sighVolatilityHarvesterContract = ISIGHVolatilityHarvester(globalAddressesProvider.getSIGHVolatilityHarvester());
        require(address(sighVolatilityHarvesterContract) != address(0));

        underlyingInstrumentAddress = _underlyingAsset;
        iToken = IIToken(_iTokenAddress) ;
        stableDebtToken = IStableDebtToken(_stableDebtTokenAddress) ;
        variableDebtToken = IVariableDebtToken(_variableDebtTokenTokenAddress) ;

    }

// ##########################################
// ####### FUNCTIONS WHICH ACCURE SIGH ######
// ##########################################

    function accureSIGHForLiquidityStream(address user) external override onlyITokenContract {
        accureSIGHForLiquidityStreamInternal(user);
    }

    function accureSIGHForBorrowingStream(address user) external override onlyDebtTokens {
        accureSIGHForBorrowingStreamInternal(user);
    }

    function accureSIGHForLiquidityStreamInternal(address user) internal {
        uint supplyIndex = sighVolatilityHarvesterContract.getInstrumentSupplyIndex( underlyingInstrumentAddress );      // Instrument index retreived from the SIGHVolatilityHarvester Contract
        require(supplyIndex > 0, "SIGH Volatility Harvester returned invalid supply Index for the instrument");

        uint totalBalance = iToken.averageBalanceOf(user); // get average balance

        Double memory userIndex = Double({mantissa: user_SIGH_States[user].liquidityStreamIndex}) ;               // Stored User Index
        Double memory instrumentIndex = Double({mantissa: supplyIndex});                                          // Instrument Index
        user_SIGH_States[user].liquidityStreamIndex = instrumentIndex.mantissa;                                   // User Index is UPDATED

        if (userIndex.mantissa == 0 && instrumentIndex.mantissa > 0) {
            userIndex.mantissa = instrumentIndex.mantissa; // sighInitialIndex;
        }

        Double memory deltaIndex = sub_(instrumentIndex, userIndex);                                // , 'Distribute Supplier SIGH : supplyIndex Subtraction Underflow'

        if ( deltaIndex.mantissa > 0 && totalBalance > 0 ) {
            uint supplierSighDelta = mul_(totalBalance, deltaIndex);                                      // Supplier Delta = Balance * Double(DeltaIndex)/DoubleScale
            accureSigh(user, supplierSighDelta, true );        // ACCURED SIGH AMOUNT IS ADDED TO THE AccuredSighBalance of the Supplier
        }
    }


    function accureSIGHForBorrowingStreamInternal(address user) internal {
        uint borrowIndex = sighVolatilityHarvesterContract.getInstrumentBorrowIndex( underlyingInstrumentAddress );      // Instrument index retreived from the SIGHVolatilityHarvester Contract
        require(borrowIndex > 0, "SIGH Volatility Harvester returned invalid borrow Index for the instrument");

        // Total Balance = SUM(Redirected balances) + User's Balance (Only if it is not redirected)
        uint totalBalance = stableDebtToken.averageBalanceOf(user).add( variableDebtToken.averageBalanceOf(user) );

        Double memory userIndex = Double({ mantissa: user_SIGH_States[user].borrowingStreamIndex }) ;      // Stored User Index
        Double memory instrumentIndex = Double({mantissa: borrowIndex});                        // Instrument Index
        user_SIGH_States[user].borrowingStreamIndex = instrumentIndex.mantissa;                                   // User Index is UPDATED

        if (userIndex.mantissa == 0 && instrumentIndex.mantissa > 0) {
            userIndex.mantissa = instrumentIndex.mantissa; // sighInitialIndex;
        }

        Double memory deltaIndex = sub_(instrumentIndex, userIndex);                                // , 'Distribute Supplier SIGH : supplyIndex Subtraction Underflow'

        if ( deltaIndex.mantissa > 0 && totalBalance > 0 ) {
            uint borrowerSighDelta = mul_(totalBalance, deltaIndex);                                      // Supplier Delta = Balance * Double(DeltaIndex)/DoubleScale
            accureSigh(user, borrowerSighDelta, false );        // ACCURED SIGH AMOUNT IS ADDED TO THE AccuredSighBalance of the Supplier or the address to which SIGH is being redirected to
        }
    }


// ###########################################################################
// ###########################################################################
// ############ ______SIGH ACCURING AND STREAMING FUNCTIONS______ ############
// ############ 1. claimSIGH() [EXTERNAL]  : Accepts an array of users. Same as 1 but for array of users.
// ############ 2. claimMySIGH() [EXTERNAL] : All accured SIGH is transferred to the transacting account.
// ############ 1. accureSigh() [INTERNAL] :
// ############ 4. claimSighInternal() [INTERNAL] : Called from 1. and 2.
// ###########################################################################
// ###########################################################################

    function claimSIGH(address[] memory users) onlyOverlyingTokens override external {
        for (uint i;i < users.length; i++) {
            claimSighInternal(users[i]);
        }
    }

    function claimMySIGH(address user) onlyOverlyingTokens override external {
        claimSighInternal(user);
    }

    function claimSighInternal(address user) internal {
        accureSIGHForLiquidityStreamInternal(user);
        accureSIGHForBorrowingStreamInternal(user);
        if (AccuredSighBalance[user] > 0) {
            AccuredSighBalance[user] = sighVolatilityHarvesterContract.transferSighTotheUser( underlyingInstrumentAddress, user, AccuredSighBalance[user] ); // Pending Amount Not Transferred is returned
        }
    }

    /**
     * @notice Accured SIGH amount is added to the ACCURED_SIGH_BALANCES of the Supplier/Borrower or the address to which SIGH is being redirected to.
     * @param user The user for which SIGH is being accured
     * @param accuredSighAmount The amount of SIGH accured
     */
    function accureSigh( address user, uint accuredSighAmount, bool isLiquidityStream ) internal {
        AccuredSighBalance[user] = AccuredSighBalance[user].add(accuredSighAmount);   // Accured SIGH added to the redirected user's sigh balance                    
        emit SighAccured( underlyingInstrumentAddress, user, isLiquidityStream, accuredSighAmount, AccuredSighBalance[user] );
        if ( AccuredSighBalance[user] > sigh_Transfer_Threshold ) {   // SIGH is Transferred if SIGH_ACCURED_BALANCE > 1e18 SIGH
            AccuredSighBalance[user] = sighVolatilityHarvesterContract.transferSighTotheUser( underlyingInstrumentAddress, user, AccuredSighBalance[user] ); // Pending Amount Not Transferred is returned
        }
    }

// #############################################################
// #############  FUNCTIONS RELATED TO FEE    ##################
// #############################################################

  function updatePlatformFee(address user, uint platformFeeIncrease, uint platformFeeDecrease) external onlyDebtTokens override {
      platformFee[user] = platformFee[user].add(platformFeeIncrease).sub(platformFeeDecrease);
  }

  function updateReserveFee(address user, uint reserveFeeIncrease, uint reserveFeeDecrease) external onlyDebtTokens override {
      reserveFee[user] = reserveFee[user].add(reserveFeeIncrease).sub(reserveFeeDecrease);
  }

  function getPlatformFee(address user) external view override returns (uint) {
    return platformFee[user];
  }

  function getReserveFee(address user)  external view override returns (uint) {
    return reserveFee[user];
  }

// ###########################################################################
// ###########################################################################
// #############  VIEW FUNCTIONS ($SIGH STREAMS RELATED)    ################## 
// ###########################################################################
// ###########################################################################

    function getSighAccured(address account) external view override returns (uint) {
        return AccuredSighBalance[account];
    }

// ###########################################################################
// ###### SAFE MATH ######
// ###########################################################################

    function sub_(Double memory a, Double memory b) pure internal returns (Double memory) {
        require(b.mantissa <= a.mantissa, "SIGH Stream: Double Mantissa Subtraction underflow, amount to be subtracted greater than the amount from which it needs to be subtracted");
        uint result = a.mantissa - b.mantissa;
        return Double({mantissa: result});
    }


    function mul_(uint a, Double memory b) pure internal returns (uint) {
        if (a == 0 || b.mantissa == 0) {
            return 0;
        }
        uint c = a * b.mantissa;
        require( (c / a) == b.mantissa, "SIGH Stream: Multiplication (uint * Double) let to overflow");
        uint doubleScale = 1e36;
        return (c / doubleScale);
    }
    
}