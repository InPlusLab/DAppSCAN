// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

/**
 * @title Sigh Volatility Harvester Contract
 * @notice Handles the SIGH Loss Minimizing Mechanism for the Lending Protocol
 * @dev Accures SIGH for the supported markets based on losses made every 24 hours, along with Staking speeds. This accuring speed is updated every hour
 * @author _astromartian
 */

import {Exponential} from "../lendingProtocol/libraries/math/Exponential.sol";
import {VersionedInitializable} from "../dependencies/upgradability/VersionedInitializable.sol";

import {GlobalAddressesProvider} from "../GlobalAddressesProvider/GlobalAddressesProvider.sol";
import {ERC20} from "../dependencies/openzeppelin/token/ERC20/ERC20.sol";
import {IPriceOracleGetter} from "../../interfaces/IPriceOracleGetter.sol";
import {ILendingPool} from "../../interfaces/lendingProtocol/ILendingPool.sol";
import {ISIGHVolatilityHarvester} from "../../interfaces/SIGHContracts/ISIGHVolatilityHarvester.sol";


contract SIGHVolatilityHarvester is ISIGHVolatilityHarvester, Exponential,  VersionedInitializable {
    
// ######## CONTRACT ADDRESSES ########
    GlobalAddressesProvider public addressesProvider;
    ERC20 public Sigh_Address;
    IPriceOracleGetter public oracle;
    address private Eth_Oracle_Address;
    ILendingPool public lendingPool;

    uint constant sighInitialIndex = 1e36;                              //  The initial SIGH index for an instrument

    Exp private cryptoMarketSentiment = Exp({mantissa: 1e18 });  

    // TOTAL Protocol Volatility Values (Current Session)
    uint256 private last24HrsTotalProtocolVolatility = 0;
    uint256 private last24HrsSentimentProtocolVolatility = 0;
    uint256 private deltaBlockslast24HrSession = 0;
    
    // SIGH Speed is set by SIGH Finance Manager. SIGH Speed Used = Calculated based on "cryptoMarketSentiment" & "last24HrsSentimentProtocolVolatility"
    uint private SIGHSpeed;
    uint private SIGHSpeedUsed;

    address[] private all_Instruments;    // LIST OF INSTRUMENTS 

// ######## INDIVIDUAL INSTRUMENT STATE ########

    struct SupportedInstrument {
        bool isListed;
        bool isSIGHMechanismActivated;
        string symbol;
        uint8 decimals;
        address iTokenAddress;
        address stableDebtToken;
        address variableDebtToken;
        address sighStreamAddress;
        uint supplyindex;
        uint256 supplylastupdatedblock;
        uint borrowindex;
        uint256 borrowlastupdatedblock;
    }

    mapping (address => SupportedInstrument) private crypto_instruments;    // FINANCIAL INSTRUMENTS
    
// ######## 24 HOUR PRICE HISTORY FOR EACH INSTRUMENT AND THE BLOCK NUMBER WHEN THEY WERE TAKEN ########

    struct InstrumentPriceCycle {
        uint256[24] recordedPriceSnapshot;
        uint32 initializationCounter;
    }

    mapping(address => InstrumentPriceCycle) private instrumentPriceCycles;    
    uint256[24] private blockNumbersForPriceSnapshots_;
    uint224 private curClock;
    uint256 private curEpoch;    

// ######## SIGH DISTRIBUTION SPEED FOR EACH INSTRUMENT ########

    struct Instrument_Sigh_Mechansim_State {
        uint8 side;                                          // side = enum{Suppliers,Borrowers,inactive}
        uint256 bearSentiment;                               // Volatility Limit Ratio = bearSentiment (if side == Suppliers)
        uint256 bullSentiment;                               // Volatility Limit Ratio = bearSentiment (if side == Borrowers)
        uint256 _total24HrVolatility;                        // TOTAL VOLATILITY = Total Compounded Balance * Price Difference
        uint256 _total24HrSentimentVolatility;               // Volatility Limit Amount = TOTAL VOLATILITY * (Volatility Limit Ratio) / 1e18
        uint256 percentTotalVolatility;                      // TOTAL VOLATILITY / last24HrsTotalProtocolVolatility
        uint256 percentTotalSentimentVolatility;             // Volatility Limit Amount / last24HrsSentimentProtocolVolatility
        uint256 suppliers_Speed;
        uint256 borrowers_Speed;
        uint256 staking_Speed;
    }

    mapping(address => Instrument_Sigh_Mechansim_State) private Instrument_Sigh_Mechansim_States;
    uint256 private deltaTimestamp = 3600; // 60 * 60 
    uint256 private prevHarvestRefreshTimestamp;


    // ####################################
    // ############## EVENTS ##############
    // ####################################

    event InstrumentAdded (address instrumentAddress_, address iTokenAddress, address sighStreamAddress,  uint8 decimals);
    event InstrumentRemoved(address _instrument);
    event InstrumentSIGHStateUpdated( address instrument_, bool isSIGHMechanismActivated, uint bearSentiment, uint bullSentiment );

    event SIGHSpeedUpdated(uint oldSIGHSpeed, uint newSIGHSpeed);     /// Emitted when SIGH speed is changed
    event CryptoMarketSentimentUpdated( uint cryptoMarketSentiment );
    event minimumTimestampForSpeedRefreshUpdated( uint prevdeltaTimestamp,uint newdeltaTimestamp );
    event EthereumOracleAddressUpdated(address ethOracleAddress);
    event StakingSpeedUpdated(address instrumentAddress_ , uint prevStakingSpeed, uint new_staking_Speed);
    
    event PriceSnapped(address instrument, uint prevPrice, uint currentPrice, uint deltaBlocks, uint currentClock );   
    event MaxSIGHSpeedCalculated(uint _SIGHSpeed, uint _SIGHSpeedUsed, uint _totalVolatilityLimitPerBlock, uint _maxVolatilityToAddressPerBlock, uint _max_SIGHDistributionLimitDecimalsAdjusted );
    event InstrumentVolatilityCalculated(address _Instrument, uint bullSentiment, uint bearSentiment, uint _total24HrVolatility , uint _total24HrSentimentVolatility);
    event refreshingSighSpeeds( address _Instrument, uint8 side,  uint supplierSpeed, uint borrowerSpeed, uint _percentTotalSentimentVolatility, uint _percentTotalVolatility );
    

    event SIGHSupplyIndexUpdated(address instrument, uint totalCompoundedSupply, uint sighAccured, uint ratioMantissa, uint newIndexMantissa);
    event SIGHBorrowIndexUpdated(address instrument, uint totalCompoundedStableBorrows, uint totalCompoundedVariableBorrows, uint sighAccured, uint ratioMantissa, uint newIndexMantissa );

    event AccuredSIGHTransferredToTheUser(address instrument, address user, uint sigh_Amount );

// #######################################################
// ##############        MODIFIERS          ##############
// #######################################################
        
    //only lendingPool can use functions affected by this modifier
    modifier onlyLendingPool {
        require(address(lendingPool) == msg.sender, "The caller must be the Lending pool contract");
        _;
    }   
    
    //only SIGH Distribution Manager can use functions affected by this modifier
    modifier onlySighFinanceConfigurator {
        require(addressesProvider.getSIGHFinanceConfigurator() == msg.sender, "The caller must be the SIGH Finanace Configurator Contract");
        _;
    }

    // This function can only be called by the Instrument's IToken Contract
    modifier onlySighStreamContract(address instrument) {
           SupportedInstrument memory currentInstrument = crypto_instruments[instrument];
           require( currentInstrument.isListed, "This instrument is not supported by SIGH Distribution Handler");
           require( msg.sender == currentInstrument.sighStreamAddress, "This function can only be called by the Instrument's SIGH Streams Handler Contract");
        _;
    }
        
// ######################################################################################
// ##############        PROXY RELATED  & ADDRESSES INITIALIZATION        ###############
// ######################################################################################

    uint256 constant private SIGH_DISTRIBUTION_REVISION = 0x1;

    function getRevision() internal pure override returns(uint256) {
        return SIGH_DISTRIBUTION_REVISION;
    }
    
    function initialize( GlobalAddressesProvider addressesProvider_) public initializer {   // 
        addressesProvider = addressesProvider_;
        refreshConfigInternal(); 
    }

    function refreshConfig() external override onlySighFinanceConfigurator {
        refreshConfigInternal();
    }

    function refreshConfigInternal() internal {
        Sigh_Address = ERC20(addressesProvider.getSIGHAddress());
        oracle = IPriceOracleGetter( addressesProvider.getPriceOracle() );
        lendingPool = ILendingPool(addressesProvider.getLendingPool());
    }
    
    
// #####################################################################################################################################################
// ##############        ADDING INSTRUMENTS AND ENABLING / DISABLING SIGH's LOSS MINIMIZING DISTRIBUTION MECHANISM       ###############################
// ##############        1. addInstrument() : Adds an instrument. Called by LendingPool                              ######################################################
// ##############        2. removeInstrument() : Instrument supported by Sigh Distribution. Called by Sigh Finance Configurator   #####################
// ##############        3. Instrument_SIGH_StateUpdated() : Activate / Deactivate SIGH Mechanism, update Volatility Limits for Suppliers / Borrowers ###############
// #####################################################################################################################################################

    /**
    * @dev adds an instrument - Called by LendingPool Core when an instrument is added to the Lending Protocol
    * @param _instrument the instrument object
    * @param _iTokenAddress the address of the overlying iToken contract
    * @param _decimals the number of decimals of the underlying asset
    **/
    function addInstrument( address _instrument, address _iTokenAddress,address _stableDebtToken,address _variableDebtToken, address _sighStreamAddress, uint8 _decimals ) external override returns (bool) {
        require(addressesProvider.getLendingPoolConfigurator() == msg.sender,'Not Lending Pool Configurator');
        require(!crypto_instruments[_instrument].isListed ,"Instrument already supported.");

        all_Instruments.push(_instrument); // ADD THE INSTRUMENT TO THE LIST OF SUPPORTED INSTRUMENTS
        ERC20 instrumentContract = ERC20(_iTokenAddress);

        // STATE UPDATED : INITIALIZE INNSTRUMENT DATA
        crypto_instruments[_instrument] = SupportedInstrument( {  isListed: true, 
                                                                symbol: instrumentContract.symbol(),
                                                                iTokenAddress: _iTokenAddress,
                                                                stableDebtToken: _stableDebtToken,
                                                                variableDebtToken: _variableDebtToken,
                                                                sighStreamAddress: _sighStreamAddress,
                                                                decimals: uint8(_decimals),
                                                                isSIGHMechanismActivated: false, 
                                                                supplyindex: sighInitialIndex, // ,"sighInitialIndex exceeds 224 bits"), 
                                                                supplylastupdatedblock: getBlockNumber(), 
                                                                borrowindex : sighInitialIndex, //,"sighInitialIndex exceeds 224 bits"), 
                                                                borrowlastupdatedblock : getBlockNumber()
                                                                } );
        // STATE UPDATED : INITITALIZE INSTRUMENT SPEEDS
        Instrument_Sigh_Mechansim_States[_instrument] = Instrument_Sigh_Mechansim_State({ 
                                                            side: uint8(0) ,
                                                            bearSentiment : uint(1e18),
                                                            bullSentiment: uint(1e18),
                                                            suppliers_Speed: uint(0),
                                                            borrowers_Speed: uint(0),
                                                            staking_Speed: uint(0),
                                                            _total24HrVolatility: uint(0),
                                                            _total24HrSentimentVolatility: uint(0),
                                                            percentTotalVolatility: uint(0),
                                                            percentTotalSentimentVolatility: uint(0)
                                                        } );
                                                        

        // STATE UPDATED : INITIALIZE PRICECYCLES
        if ( instrumentPriceCycles[_instrument].initializationCounter == 0 ) {
            uint256[24] memory emptyPrices;
            instrumentPriceCycles[_instrument] = InstrumentPriceCycle({ recordedPriceSnapshot : emptyPrices, initializationCounter: uint32(0) }) ;
        }   

        emit InstrumentAdded(_instrument,_iTokenAddress, _sighStreamAddress,  _decimals);
        return true;
    }

    /**
    * @dev removes an instrument - Called by LendingPool Core when an instrument is removed from the Lending Protocol
    * @param _instrument the instrument object
    **/
    function removeInstrument( address _instrument ) external override onlyLendingPool returns (bool) {
        require(crypto_instruments[_instrument].isListed ,"Instrument already supported.");
        require(updatedInstrumentIndexesInternal(), "Updating Instrument Indexes Failed");       //  accure the indexes 

        uint index = 0;
        uint length_ = all_Instruments.length;
        for (uint i = 0 ; i < length_ ; i++) {
            if (all_Instruments[i] == _instrument) {
                index = i;
                break;
            }
        }
        all_Instruments[index] = all_Instruments[length_ - 1];
        all_Instruments.pop();
        uint newLen = length_ - 1;
        require(all_Instruments.length == newLen,"Instrument not properly removed from the list of instruments supported");
        
        delete crypto_instruments[_instrument];
        delete Instrument_Sigh_Mechansim_States[_instrument];
        delete instrumentPriceCycles[_instrument];

        emit InstrumentRemoved(_instrument);
        return true;
    }



    /**
    * @dev Instrument to be convered under the SIGH DIstribution Mechanism and the associated Volatility Limits - Decided by the SIGH Finance Manager who 
    * can call this function through the Sigh Finance Configurator
    * @param instrument_ the instrument object
    **/
    function Instrument_SIGH_StateUpdated(address instrument_, uint _bearSentiment,uint _bullSentiment, bool _isSIGHMechanismActivated  ) external override onlySighFinanceConfigurator returns (bool) {                   //
        require(crypto_instruments[instrument_].isListed ,"Instrument not supported.");
        require( _bearSentiment >= 0.01e18, 'The new Volatility Limit for Suppliers must be greater than 0.01e18 (1%)');
        require( _bearSentiment <= 10e18, 'The new Volatility Limit for Suppliers must be less than 10e18 (10x)');
        require( _bullSentiment >= 0.01e18, 'The new Volatility Limit for Borrowers must be greater than 0.01e18 (1%)');
        require( _bullSentiment <= 10e18, 'The new Volatility Limit for Borrowers must be less than 10e18 (10x)');
        refreshSIGHSpeeds(); 
        
        crypto_instruments[instrument_].isSIGHMechanismActivated = _isSIGHMechanismActivated;                       // STATE UPDATED
        Instrument_Sigh_Mechansim_States[instrument_].bearSentiment = _bearSentiment;      // STATE UPDATED
        Instrument_Sigh_Mechansim_States[instrument_].bullSentiment = _bullSentiment;      // STATE UPDATED
        
        emit InstrumentSIGHStateUpdated( instrument_, crypto_instruments[instrument_].isSIGHMechanismActivated, Instrument_Sigh_Mechansim_States[instrument_].bearSentiment, Instrument_Sigh_Mechansim_States[instrument_].bullSentiment );
        return true;
    }
    

// ###########################################################################################################################
// ##############        GLOBAL SIGH SPEED AND SIGH SPEED RATIO FOR A MARKET          ########################################
// ##############        1. updateSIGHSpeed() : Governed by Sigh Finance Manager          ####################################
// ##############        3. updateStakingSpeedForAnInstrument():  Decided by the SIGH Finance Manager          ###############
// ##############        5. updatedeltaTimestampRefresh() : Decided by the SIGH Finance Manager           ###############
// ###########################################################################################################################

    /**
     * @notice Sets the amount of Global SIGH distributed per block - - Decided by the SIGH Finance Manager who 
     * can call this function through the Sigh Finance Configurator
     * @param SIGHSpeed_ The amount of SIGH wei per block to distribute
     */
    function updateSIGHSpeed(uint SIGHSpeed_) external override onlySighFinanceConfigurator returns (bool) {
        refreshSIGHSpeeds();
        uint oldSpeed = SIGHSpeed;
        SIGHSpeed = SIGHSpeed_;                                 // STATE UPDATED
        emit SIGHSpeedUpdated(oldSpeed, SIGHSpeed);
        return true;
    }
    
    /**
     * @notice Sets the staking speed for an Instrument - Decided by the SIGH Finance Manager who 
     * can call this function through the Sigh Finance Configurator
     * @param instrument_ The instrument
     * @param newStakingSpeed The additional SIGH staking speed assigned to the Instrument
     */
    function updateStakingSpeedForAnInstrument(address instrument_, uint newStakingSpeed) external override onlySighFinanceConfigurator returns (bool) {     //
        require(crypto_instruments[instrument_].isListed ,"Instrument not supported.");
        
        uint prevStakingSpeed = Instrument_Sigh_Mechansim_States[instrument_].staking_Speed;
        Instrument_Sigh_Mechansim_States[instrument_].staking_Speed = newStakingSpeed;                    // STATE UPDATED

        emit StakingSpeedUpdated(instrument_, prevStakingSpeed, Instrument_Sigh_Mechansim_States[instrument_].staking_Speed);
        return true;
    }


    /**
     * @notice Updates the minimum blocks to be mined before speed can be refreshed again  - Decided by the SIGH Finance Manager who 
     * can call this function through the Sigh Finance Configurator
     * @param deltaTimestampLimit The new Minimum time limit
     */   
    function updateDeltaTimestampRefresh(uint deltaTimestampLimit) external override onlySighFinanceConfigurator returns (bool) {      //
        refreshSIGHSpeeds();
        uint prevdeltaTimestamp = deltaTimestamp;
        deltaTimestamp = deltaTimestampLimit;                                         // STATE UPDATED
        emit minimumTimestampForSpeedRefreshUpdated( prevdeltaTimestamp,deltaTimestamp );
        return true;
    }

    function updateCryptoMarketSentiment( uint cryptoMarketSentiment_ ) external override onlySighFinanceConfigurator returns (bool) {
        require( cryptoMarketSentiment_ >= 0.01e18, 'The new Volatility Limit for Borrowers must be greater than 0.01e18 (1%)');
        require( cryptoMarketSentiment_ <= 10e18, 'The new Volatility Limit for Borrowers must be less than 10e18 (10x)');
        
        cryptoMarketSentiment = Exp({mantissa: cryptoMarketSentiment_ });  
        emit CryptoMarketSentimentUpdated( cryptoMarketSentiment.mantissa );
        return true;
    }

    function updateETHOracleAddress( address _EthOracleAddress ) external override onlySighFinanceConfigurator returns (bool) {
        require( _EthOracleAddress != address(0), 'ETH Oracle address not valid');
        require(oracle.getAssetPrice(_EthOracleAddress) > 0, 'Oracle returned invalid price');   
        require(oracle.getAssetPriceDecimals(_EthOracleAddress) > 0, 'Oracle returned invalid decimals');   
        
        Eth_Oracle_Address = _EthOracleAddress;       
        emit EthereumOracleAddressUpdated( Eth_Oracle_Address );
        return true;
    }

    // #########################################################################################################
    // ################ REFRESH SIGH DISTRIBUTION SPEEDS FOR INSTRUMENTS (INITIALLY EVERY HOUR) ################
    // #########################################################################################################

    /**
     * @notice Recalculate and update SIGH speeds for all Supported SIGH markets
     */
    function refreshSIGHSpeeds() public override returns (bool) {
        uint256 timeElapsedSinceLastRefresh = sub_(block.timestamp , prevHarvestRefreshTimestamp, "Refresh SIGH Speeds : Subtraction underflow for timestamps"); 

        if ( timeElapsedSinceLastRefresh >= deltaTimestamp) {
            refreshSIGHSpeedsInternal();
            prevHarvestRefreshTimestamp = block.timestamp;                                        // STATE UPDATED
            return true;
        }
        return false;
    }



    /**
     * @notice Recalculate and update SIGH speeds for all Supported SIGH markets
     * 1. Instrument indexes for all instruments updated
     * 2. Delta blocks (past 24 hours) calculated and current block number (for price snapshot) updated
     * 3. 1st loop over all instruments --> Average loss (per block) for each of the supported instruments
     *    along with the total lending protocol's loss (per block) calculated and stored price snapshot is updated
     * 4. The Sigh speed that will be used for speed refersh calculated (provided if is needed to be done) 
     * 5. 1st loop over all instruments -->  Sigh Distribution speed (Loss driven speed + staking speed) calculated for 
     *    each instrument
     * 5.1 Current Clock updated
     */    
    function refreshSIGHSpeedsInternal() internal {
        address[] memory all_Instruments_ = all_Instruments;
        uint deltaBlocks_ = sub_( block.timestamp , blockNumbersForPriceSnapshots_[curClock], "DeltaTimestamp resulted in Underflow");       // Delta Blocks over past 24 hours
        blockNumbersForPriceSnapshots_[curClock] = block.timestamp;                                                                    // STATE UPDATE : Block Number for the priceSnapshot Updated

        require(updatedInstrumentIndexesInternal(), "Updating Instrument Indexes Failed");       //  accure the indexes 

        Exp memory totalProtocolVolatility = Exp({mantissa: 0});                            // TOTAL LOSSES (Over past 24 hours)
        Exp memory totalProtocolVolatilityLimit = Exp({mantissa: 0});                            // TOTAL LOSSES (Over past 24 hours)
        
        // Price Snapshot for current clock replaces the pervious price snapshot
        // DELTA BLOCKS = CURRENT BLOCK - 24HRS_OLD_STORED_BLOCK_NUMBER
        // LOSS PER INSTRUMENT = PREVIOUS PRICE (STORED) - CURRENT PRICE (TAKEN FROM ORACLE)
        // TOTAL VOLATILITY OF AN INSTRUMENT = LOSS PER INSTRUMENT * TOTAL COMPOUNDED LIQUIDITY
        // VOLATILITY OF AN INSTRUMENT TO BE ACCOUNTED FOR = TOTAL VOLATILITY OF AN INSTRUMENT * VOLATILITY LIMIT (DIFFERENT FOR SUPPLIERS/BORROWERS OF INSTRUMENT)
        // TOTAL PROTOCOL VOLATILITY =  + ( VOLATILITY OF AN INSTRUMENT TO BE ACCOUNTED FOR )
        for (uint i = 0; i < all_Instruments_.length; i++) {

            address _currentInstrument = all_Instruments_[i];       // Current Instrument
            
            // UPDATING PRICE SNAPSHOTS
            Exp memory previousPriceUSD = Exp({ mantissa: instrumentPriceCycles[_currentInstrument].recordedPriceSnapshot[curClock] });            // 24hr old price snapshot
            Exp memory currentPriceUSD = Exp({ mantissa: oracle.getAssetPrice( _currentInstrument ) });                                            // current price from the oracle
            require ( currentPriceUSD.mantissa > 0, "refreshSIGHSpeedsInternal : Oracle returned Invalid Price" );
            instrumentPriceCycles[_currentInstrument].recordedPriceSnapshot[curClock] =  uint256(currentPriceUSD.mantissa); //  STATE UPDATED : PRICE SNAPSHOT TAKEN        
            emit PriceSnapped(_currentInstrument, previousPriceUSD.mantissa, instrumentPriceCycles[_currentInstrument].recordedPriceSnapshot[curClock], deltaBlocks_, curClock );

            if ( !crypto_instruments[_currentInstrument].isSIGHMechanismActivated || instrumentPriceCycles[_currentInstrument].initializationCounter != uint32(24) ) {     // if LOSS MINIMIZNG MECHANISM IS NOT ACTIVATED FOR THIS INSTRUMENT
                // STATE UPDATE
                Instrument_Sigh_Mechansim_States[_currentInstrument].bearSentiment = 1e18;
                Instrument_Sigh_Mechansim_States[_currentInstrument].bullSentiment = 1e18;
                Instrument_Sigh_Mechansim_States[_currentInstrument].side = uint8(0);
                Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrVolatility =  uint(0);
                Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrSentimentVolatility =  uint(0);
                //    Newly Sighed Instrument needs to reach 24 (priceSnapshots need to be taken) before it can be assigned a Sigh Speed based on VOLATILITY   
                if (instrumentPriceCycles[_currentInstrument].initializationCounter < uint32(24) ) {
                    instrumentPriceCycles[_currentInstrument].initializationCounter = uint32(add_(instrumentPriceCycles[_currentInstrument].initializationCounter , uint32(1) , 'Price Counter addition failed.'));  // STATE UPDATE : INITIALIZATION COUNTER UPDATED
                }
            }
            else {
                MathError error;
                Exp memory volatility = Exp({mantissa: 0});
                Exp memory lossPerInstrument = Exp({mantissa: 0});   
                Exp memory instrumentVolatilityLimit = Exp({mantissa: 0});
                
                if ( greaterThanExp(previousPriceUSD , currentPriceUSD) ) {   // i.e the price has decreased so we calculate Losses accured by Suppliers of the Instrument
                    uint totalCompoundedLiquidity = ERC20(crypto_instruments[_currentInstrument].iTokenAddress).totalSupply(); // Total Compounded Liquidity
                    ( error, lossPerInstrument) = subExp( previousPriceUSD , currentPriceUSD );       
                    ( error, volatility ) = mulScalar( lossPerInstrument, totalCompoundedLiquidity );
                    instrumentVolatilityLimit = Exp({mantissa: Instrument_Sigh_Mechansim_States[_currentInstrument].bearSentiment });
                    // STATE UPDATE
                    Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrVolatility =  adjustForDecimalsInternal(volatility.mantissa, crypto_instruments[_currentInstrument].decimals , oracle.getAssetPriceDecimals(_currentInstrument) );
                    Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrSentimentVolatility =  mul_(Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrVolatility , instrumentVolatilityLimit );
                    Instrument_Sigh_Mechansim_States[_currentInstrument].side = uint8(1);

                    uint256 _bear = mul_(Instrument_Sigh_Mechansim_States[_currentInstrument].bearSentiment,167);
                    _bear = add_(_bear,1e18);
                    Instrument_Sigh_Mechansim_States[_currentInstrument].bearSentiment = div_(_bear,168);

                    uint256 _bull = mul_(Instrument_Sigh_Mechansim_States[_currentInstrument].bullSentiment,167);
                    Instrument_Sigh_Mechansim_States[_currentInstrument].bullSentiment = div_(_bull,168);

                }
                else {                                              // i.e the price has increased so we calculate Losses accured by Borrowers of the Instrument
                    uint totalVariableBorrows = ERC20(crypto_instruments[_currentInstrument].variableDebtToken).totalSupply();
                    uint totalStableBorrows =  ERC20(crypto_instruments[_currentInstrument].stableDebtToken).totalSupply();
                    uint totalCompoundedBorrows =  add_(totalVariableBorrows,totalStableBorrows,'Compounded Borrows Addition gave error'); 
                    ( error, lossPerInstrument) = subExp( currentPriceUSD, previousPriceUSD );       
                    ( error, volatility ) = mulScalar( lossPerInstrument, totalCompoundedBorrows );
                    instrumentVolatilityLimit = Exp({mantissa: Instrument_Sigh_Mechansim_States[_currentInstrument].bullSentiment });
                    // STATE UPDATE
                    Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrVolatility = adjustForDecimalsInternal(volatility.mantissa , crypto_instruments[_currentInstrument].decimals , oracle.getAssetPriceDecimals(_currentInstrument) );
                    Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrSentimentVolatility =  mul_(Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrVolatility , instrumentVolatilityLimit );
                    Instrument_Sigh_Mechansim_States[_currentInstrument].side = uint8(2);

                    uint256 _bull = mul_(Instrument_Sigh_Mechansim_States[_currentInstrument].bullSentiment,167);
                    _bull = add_(_bull,1e18);
                    Instrument_Sigh_Mechansim_States[_currentInstrument].bullSentiment = div_(_bull,168);

                    uint256 _bear = mul_(Instrument_Sigh_Mechansim_States[_currentInstrument].bearSentiment,167);
                    Instrument_Sigh_Mechansim_States[_currentInstrument].bearSentiment = div_(_bear,168);

                }
                //  Total Protocol Volatility  += Instrument Volatility 
                totalProtocolVolatility = add_(totalProtocolVolatility, Exp({mantissa: Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrVolatility}) );            
                //  Total Protocol Volatility Limit  += Instrument Volatility Limit Amount                 
                 totalProtocolVolatilityLimit = add_(totalProtocolVolatilityLimit, Exp({mantissa: Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrSentimentVolatility})) ;            
            }
            
            emit InstrumentVolatilityCalculated(_currentInstrument, Instrument_Sigh_Mechansim_States[_currentInstrument].bullSentiment, Instrument_Sigh_Mechansim_States[_currentInstrument].bearSentiment, Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrVolatility , Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrSentimentVolatility);
        }
        
       
        last24HrsTotalProtocolVolatility = totalProtocolVolatility.mantissa;              // STATE UPDATE : Last 24 Hrs Protocol Volatility  (i.e SUM(_total24HrVolatility for Instruments))  Updated
        last24HrsSentimentProtocolVolatility = totalProtocolVolatilityLimit.mantissa;     // STATE UPDATE : Last 24 Hrs Protocol Volatility Limit (i.e SUM(_total24HrSentimentVolatility for Instruments)) Updated
        deltaBlockslast24HrSession = deltaBlocks_;                                        // STATE UPDATE :
        
        // STATE UPDATE :: CALCULATING SIGH SPEED WHICH IS TO BE USED FOR CALCULATING EACH INSTRUMENT's SIGH DISTRIBUTION SPEEDS
        SIGHSpeedUsed = SIGHSpeed;

        (MathError error, Exp memory totalVolatilityLimitPerBlock) = divScalar(Exp({mantissa: last24HrsSentimentProtocolVolatility }) , deltaBlocks_);   // Total Volatility per Block
        calculateMaxSighSpeedInternal( totalVolatilityLimitPerBlock.mantissa ); 
        
        // ###### Updates the Speed (Volatility Driven) for the Supported Instruments ######
        updateSIGHDistributionSpeeds();
        require(updateCurrentClockInternal(), "Updating CLock Failed");                         // Updates the Clock    
    }


    //  Updates the Supply & Borrow Indexes for all the Supported Instruments
    function updatedInstrumentIndexesInternal() internal returns (bool) {
        for (uint i = 0; i < all_Instruments.length; i++) {
            address currentInstrument = all_Instruments[i];
            updateSIGHSupplyIndexInternal(currentInstrument);
            updateSIGHBorrowIndexInternal(currentInstrument);
        }
        return true;
    }
    
    // UPDATES SIGH DISTRIBUTION SPEEDS
    function updateSIGHDistributionSpeeds() internal returns (bool) {
        
        for (uint i=0 ; i < all_Instruments.length ; i++) {

            address _currentInstrument = all_Instruments[i];       // Current Instrument
            Exp memory limitVolatilityRatio =  Exp({mantissa: 0});
            Exp memory totalVolatilityRatio =  Exp({mantissa: 0});
            MathError error;
            
            if ( last24HrsSentimentProtocolVolatility > 0 && Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrSentimentVolatility > 0 ) {
                ( error, limitVolatilityRatio) = getExp(Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrSentimentVolatility, last24HrsSentimentProtocolVolatility);
                ( error, totalVolatilityRatio) = getExp(Instrument_Sigh_Mechansim_States[_currentInstrument]._total24HrVolatility, last24HrsTotalProtocolVolatility);
                // CALCULATING $SIGH SPEEDS
                if (Instrument_Sigh_Mechansim_States[_currentInstrument].side == uint8(1) ) {
                    // STATE UPDATE
                    Instrument_Sigh_Mechansim_States[_currentInstrument].suppliers_Speed = mul_(SIGHSpeedUsed, limitVolatilityRatio);                                         
                    Instrument_Sigh_Mechansim_States[_currentInstrument].borrowers_Speed = uint(0);                                                           
                } 
                else if  (Instrument_Sigh_Mechansim_States[_currentInstrument].side == uint8(2) )  {
                    // STATE UPDATE
                    Instrument_Sigh_Mechansim_States[_currentInstrument].borrowers_Speed = mul_(SIGHSpeedUsed, limitVolatilityRatio);                                       
                    Instrument_Sigh_Mechansim_States[_currentInstrument].suppliers_Speed = uint(0);                                                          
                }
            } 
            else {
                    // STATE UPDATE
                Instrument_Sigh_Mechansim_States[_currentInstrument].borrowers_Speed = uint(0);                                                               
                Instrument_Sigh_Mechansim_States[_currentInstrument].suppliers_Speed = uint(0);                                                                
            }

            Instrument_Sigh_Mechansim_States[_currentInstrument].percentTotalSentimentVolatility = mul_(10**9, limitVolatilityRatio);                                              // STATE UPDATE (LOss Ratio is instrumentVolatility/totalVolatility * 100000 )
            Instrument_Sigh_Mechansim_States[_currentInstrument].percentTotalVolatility = mul_(10**9, totalVolatilityRatio);                                              // STATE UPDATE (LOss Ratio is instrumentVolatility/totalVolatility * 100000 )
            emit refreshingSighSpeeds( _currentInstrument, Instrument_Sigh_Mechansim_States[_currentInstrument].side,  Instrument_Sigh_Mechansim_States[_currentInstrument].suppliers_Speed, Instrument_Sigh_Mechansim_States[_currentInstrument].borrowers_Speed, Instrument_Sigh_Mechansim_States[_currentInstrument].percentTotalSentimentVolatility, Instrument_Sigh_Mechansim_States[_currentInstrument].percentTotalVolatility );
        }
        return true;
    }





    // returns the currently maximum possible SIGH Distribution speed. Called only when upper check is activated
    // Updated the Global "SIGHSpeedUsed" Variable & "last24HrsSentimentProtocolVolatilityAddressedPerBlock" Variable
    function calculateMaxSighSpeedInternal( uint totalVolatilityLimitPerBlock ) internal {

        uint current_Sigh_PriceETH = oracle.getAssetPrice( address(Sigh_Address) );   
        uint sighEthPriceDecimals = oracle.getAssetPriceDecimals(address(Sigh_Address));
        require(current_Sigh_PriceETH > 0,"Oracle returned invalid $SIGH Price!");

        uint current_ETH_PriceUSD = oracle.getAssetPrice( address(Eth_Oracle_Address) );   
        uint ethPriceDecimals = oracle.getAssetPriceDecimals(address(Eth_Oracle_Address));
        require(current_ETH_PriceUSD > 0,"Oracle returned invalid ETH Price!");

        uint currentSIGH_price_USD = mul_( current_Sigh_PriceETH, current_ETH_PriceUSD);
        currentSIGH_price_USD = div_( currentSIGH_price_USD, uint( 10**(sighEthPriceDecimals) ), "Max Volatility : SIGH decimal Division gave error");

        ERC20 sighContract = ERC20(address(Sigh_Address));
        uint sighDecimals =  sighContract.decimals();

        // MAX Value that can be distributed per block through SIGH Distribution
        uint max_SIGHDistributionLimit = mul_( currentSIGH_price_USD, SIGHSpeed );   
        uint max_SIGHDistributionLimitDecimalsAdjusted = adjustForDecimalsInternal( max_SIGHDistributionLimit, sighDecimals , ethPriceDecimals  );

        // MAX Volatility that is allowed to be covered through SIGH Distribution (% of the Harvestable Volatility)
        uint maxVolatilityToAddressPerBlock = mul_(totalVolatilityLimitPerBlock, cryptoMarketSentiment ); // (a * b)/1e18 [b is in Exp Scale]


        if ( max_SIGHDistributionLimitDecimalsAdjusted >  maxVolatilityToAddressPerBlock ) {
            uint maxVolatilityToAddress_SIGHdecimalsMul = mul_( maxVolatilityToAddressPerBlock, uint(10**(sighDecimals)), "Max Volatility : SIGH Decimals multiplication gave error" );
            uint maxVolatilityToAddress_PricedecimalsMul = mul_( maxVolatilityToAddress_SIGHdecimalsMul, uint(10**(ethPriceDecimals)), "Max Volatility : Price Decimals multiplication gave error" );
            uint maxVolatilityToAddress_DecimalsDiv = div_( maxVolatilityToAddress_PricedecimalsMul, uint(10**18), "Max Volatility : Decimals division gave error" );
            SIGHSpeedUsed = div_( maxVolatilityToAddress_DecimalsDiv, currentSIGH_price_USD, "Max Speed division gave error" );
        }

        emit MaxSIGHSpeedCalculated(SIGHSpeed, SIGHSpeedUsed, totalVolatilityLimitPerBlock, maxVolatilityToAddressPerBlock, max_SIGHDistributionLimitDecimalsAdjusted  );
    }


    // Updates the Current CLock (global variable tracking the current hour )
    function updateCurrentClockInternal() internal returns (bool) {
        curClock = curClock == 23 ? 0 : uint224(add_(curClock,1,"curClock : Addition Failed"));
        return true;
    }

    
    function adjustForDecimalsInternal(uint _amount, uint instrumentDecimals, uint priceDecimals) internal pure returns (uint) {
        require(instrumentDecimals > 0, "Instrument Decimals cannot be Zero");
        require(priceDecimals > 0, "Oracle returned invalid price Decimals");
        uint adjused_Amount = mul_(_amount,uint(10**18),'Loss Amount multiplication Adjustment overflow');
        uint instrumentDecimalsCorrected = div_( adjused_Amount,uint(10**instrumentDecimals),'Instrument Decimals correction underflow');
        uint priceDecimalsCorrected = div_( instrumentDecimalsCorrected,uint(10**priceDecimals),'Price Decimals correction underflow');
        return priceDecimalsCorrected;
    }


    // #####################################################################################################################################
    // ################ UPDATE SIGH DISTRIBUTION INDEXES (Called from LendingPool) #####################################################
    // ################ 1. updateSIGHSupplyIndex() : Called by LendingPool              ################################################
    // ################ --> updateSIGHSupplyIndexInternal() Internal function with actual implementation  ################################## 
    // ################ 2. updateSIGHBorrowIndex() : Called by LendingPool #############################################################
    // ################ --> updateSIGHBorrowIndexInternal() : Internal function with actual implementation #################################
    // #####################################################################################################################################


    /**
     * @notice Accrue SIGH to the Instrument by updating the supply index
     * @param currentInstrument The Instrument whose supply index to update
     */
    function updateSIGHSupplyIndex(address currentInstrument) external override onlyLendingPool returns (bool) { //     // Called on each Deposit, Redeem and Liquidation (collateral)
        require(crypto_instruments[currentInstrument].isListed ,"Instrument not supported.");
        require(updateSIGHSupplyIndexInternal( currentInstrument ), "Updating Sigh Supply Indexes operation failed" );
        return true;
    }

    function updateSIGHSupplyIndexInternal(address currentInstrument) internal returns (bool) {
        uint blockNumber = getBlockNumber();

        if ( crypto_instruments[currentInstrument].supplylastupdatedblock == blockNumber ) {    // NO NEED TO ACCUR AGAIN
            return true;
        }

        SupportedInstrument storage instrumentState = crypto_instruments[currentInstrument];
        uint supplySpeed = add_(Instrument_Sigh_Mechansim_States[currentInstrument].suppliers_Speed, Instrument_Sigh_Mechansim_States[currentInstrument].staking_Speed,"Supplier speed addition with staking speed overflow" );
        uint deltaBlocks = sub_(blockNumber, uint( instrumentState.supplylastupdatedblock ), 'updateSIGHSupplyIndex : Block Subtraction Underflow');    // Delta Blocks 
        
        // WE UPDATE INDEX ONLY IF $SIGH IS ACCURING
        if (deltaBlocks > 0 && supplySpeed > 0) {       // In case SIGH would have accured
            uint sigh_Accrued = mul_(deltaBlocks, supplySpeed);                                                                         // SIGH Accured
            uint totalCompoundedLiquidity = ERC20(crypto_instruments[currentInstrument].iTokenAddress).totalSupply();                           // Total amount supplied 
            Double memory ratio = totalCompoundedLiquidity > 0 ? fraction(sigh_Accrued, totalCompoundedLiquidity) : Double({mantissa: 0});    // SIGH Accured per Supplied Instrument Token
            Double memory newIndex = add_(Double({mantissa: instrumentState.supplyindex}), ratio);                                      // Updated Index
            emit SIGHSupplyIndexUpdated( currentInstrument, totalCompoundedLiquidity, sigh_Accrued, ratio.mantissa , newIndex.mantissa);

            instrumentState.supplyindex = newIndex.mantissa;       // STATE UPDATE: New Index Committed to Storage 
        } 
        
        instrumentState.supplylastupdatedblock = blockNumber ;     // STATE UPDATE: Block number updated        
        return true;
    }



    /**
     * @notice Accrue SIGH to the market by updating the borrow index
     * @param currentInstrument The market whose borrow index to update
     */
    function updateSIGHBorrowIndex(address currentInstrument) external override onlyLendingPool returns (bool) {  //     // Called during Borrow, repay, SwapRate, Rebalance, Liquidation
        require(crypto_instruments[currentInstrument].isListed ,"Instrument not supported.");
        require( updateSIGHBorrowIndexInternal(currentInstrument), "Updating Sigh Borrow Indexes operation failed" ) ;
        return true;
    }

    function updateSIGHBorrowIndexInternal(address currentInstrument) internal returns(bool) {
        uint blockNumber = getBlockNumber();

        if ( crypto_instruments[currentInstrument].borrowlastupdatedblock == blockNumber ) {    // NO NEED TO ACCUR AGAIN
            return true;
        }

        SupportedInstrument storage instrumentState = crypto_instruments[currentInstrument];
        uint borrowSpeed = add_(Instrument_Sigh_Mechansim_States[currentInstrument].borrowers_Speed, Instrument_Sigh_Mechansim_States[currentInstrument].staking_Speed, "Supplier speed addition with staking speed overflow" );
        uint deltaBlocks = sub_(blockNumber, uint(instrumentState.borrowlastupdatedblock), 'updateSIGHBorrowIndex : Block Subtraction Underflow');         // DELTA BLOCKS
        
        uint totalVariableBorrows =   ERC20(crypto_instruments[currentInstrument].variableDebtToken).totalSupply();
        uint totalStableBorrows =   ERC20(crypto_instruments[currentInstrument].stableDebtToken).totalSupply();
        uint totalCompoundedBorrows =  add_(totalVariableBorrows,totalStableBorrows,'Compounded Borrows Addition gave error'); 
        
        if (deltaBlocks > 0 && borrowSpeed > 0) {       // In case SIGH would have accured
            uint sigh_Accrued = mul_(deltaBlocks, borrowSpeed);                             // SIGH ACCURED = DELTA BLOCKS x SIGH SPEED (BORROWERS)
            Double memory ratio = totalCompoundedBorrows > 0 ? fraction(sigh_Accrued, totalCompoundedBorrows) : Double({mantissa: 0});      // SIGH Accured per Borrowed Instrument Token
            Double memory newIndex = add_(Double({mantissa: instrumentState.borrowindex}), ratio);                      // New Index
            emit SIGHBorrowIndexUpdated( currentInstrument, totalStableBorrows, totalVariableBorrows, sigh_Accrued, ratio.mantissa , newIndex.mantissa );

            instrumentState.borrowindex = newIndex.mantissa ;  // STATE UPDATE: New Index Committed to Storage 
        } 

        instrumentState.borrowlastupdatedblock = blockNumber;   // STATE UPDATE: Block number updated        
        return true;
    }

    // #########################################################################################
    // ################### TRANSFERS THE SIGH TO THE MARKET PARTICIPANT  ###################
    // #########################################################################################

    /**
     * @notice Transfer SIGH to the user. Called by the corresponding IToken Contract of the instrument
     * @dev Note: If there is not enough SIGH, we do not perform the transfer call.
     * @param instrument The instrument for which the SIGH has been accured
     * @param user The address of the user to transfer SIGH to
     * @param sigh_Amount The amount of SIGH to (possibly) transfer
     * @return The amount of SIGH which was NOT transferred to the user
     */
    function transferSighTotheUser(address instrument, address user, uint sigh_Amount ) external override onlySighStreamContract(instrument) returns (uint) {   //
        uint sigh_not_transferred = 0;
        if ( Sigh_Address.balanceOf(address(this)) > sigh_Amount ) {   // NO SIGH TRANSFERRED IF CONTRACT LACKS REQUIRED SIGH AMOUNT
            require(Sigh_Address.transfer( user, sigh_Amount ), "Failed to transfer accured SIGH to the user." );
            emit AccuredSIGHTransferredToTheUser( instrument, user, sigh_Amount );
        }
        else {
            sigh_not_transferred = sigh_Amount;
        }
        return sigh_not_transferred;
    }

    // #########################################################
    // ################### GENERAL PARAMETER FUNCTIONS ###################
    // #########################################################

    function getSIGHBalance() public view override returns (uint) {
        uint sigh_Remaining = Sigh_Address.balanceOf(address(this));
        return sigh_Remaining;
    }

    function getAllInstrumentsSupported() external view override returns (address[] memory ) {
        return all_Instruments; 
    }
    
    function getInstrumentData (address instrument_) external override view returns (string memory symbol, address iTokenAddress, uint decimals, bool isSIGHMechanismActivated,uint256 supplyindex, uint256 borrowindex  ) {
        return ( crypto_instruments[instrument_].symbol,
                 crypto_instruments[instrument_].iTokenAddress,    
                 crypto_instruments[instrument_].decimals,    
                 crypto_instruments[instrument_].isSIGHMechanismActivated,
                 crypto_instruments[instrument_].supplyindex,
                 crypto_instruments[instrument_].borrowindex
                ); 
    }

    function getInstrumentSpeeds(address instrument) external override view returns ( uint8 side, uint suppliers_speed, uint borrowers_speed, uint staking_speed ) {
        return ( Instrument_Sigh_Mechansim_States[instrument].side,
                 Instrument_Sigh_Mechansim_States[instrument].suppliers_Speed, 
                 Instrument_Sigh_Mechansim_States[instrument].borrowers_Speed , 
                 Instrument_Sigh_Mechansim_States[instrument].staking_Speed
                );
    }
    
    function getInstrumentVolatilityStates(address instrument) external override view returns ( uint8 side, uint _total24HrSentimentVolatility, uint percentTotalSentimentVolatility, uint _total24HrVolatility, uint percentTotalVolatility  ) {
        return (Instrument_Sigh_Mechansim_States[instrument].side,
                Instrument_Sigh_Mechansim_States[instrument]._total24HrSentimentVolatility,
                Instrument_Sigh_Mechansim_States[instrument].percentTotalSentimentVolatility,
                Instrument_Sigh_Mechansim_States[instrument]._total24HrVolatility,
                Instrument_Sigh_Mechansim_States[instrument].percentTotalVolatility
                );
    }    

    function getInstrumentSighLimits(address instrument) external override view returns ( uint _bearSentiment , uint _bullSentiment ) {
    return ( Instrument_Sigh_Mechansim_States[instrument].bearSentiment, Instrument_Sigh_Mechansim_States[instrument].bullSentiment );
    }

    function getAllPriceSnapshots(address instrument_ ) external override view returns (uint256[24] memory) {
        return instrumentPriceCycles[instrument_].recordedPriceSnapshot;
    }
    
    function getBlockNumbersForPriceSnapshots() external override view returns (uint256[24] memory) {
        return blockNumbersForPriceSnapshots_;
    }

    function getSIGHSpeed() external override view returns (uint) {
        return SIGHSpeed;
    }

    function getSIGHSpeedUsed() external override view returns (uint) {
        return SIGHSpeedUsed;
    }


    function isInstrumentSupported (address instrument_) external override view returns (bool) {
        return crypto_instruments[instrument_].isListed;
    } 

    function totalInstrumentsSupported() external override view returns (uint) {
        return uint(all_Instruments.length); 
    }    

    function getInstrumentSupplyIndex(address instrument_) external override view returns (uint) {
        if (crypto_instruments[instrument_].isListed) { //"The provided instrument address is not supported");
            return crypto_instruments[instrument_].supplyindex;
        }
        return uint(0);
    }

    function getInstrumentBorrowIndex(address instrument_) external override view returns (uint) {
        if (crypto_instruments[instrument_].isListed) { //,"The provided instrument address is not supported");
            return crypto_instruments[instrument_].borrowindex;
        }
        return uint(0);
    }


    function getCryptoMarketSentiment () external override view returns (uint) {
        return cryptoMarketSentiment.mantissa;
    } 

    function checkPriceSnapshots(address instrument_, uint clock) external override view returns (uint256) {
        return instrumentPriceCycles[instrument_].recordedPriceSnapshot[clock];
    }
    
    function checkinitializationCounter(address instrument_) external override view returns (uint32) {
        return instrumentPriceCycles[instrument_].initializationCounter;
    }

    function getdeltaTimestamp() external override view returns (uint) {
        return deltaTimestamp;
    }  

    function getprevHarvestRefreshTimestamp() external override view returns (uint) {
        return prevHarvestRefreshTimestamp;
    }  

    function getBlocksRemainingToNextSpeedRefresh() external override view returns (uint) {
        uint blocksElapsed = sub_(block.number,prevHarvestRefreshTimestamp); 
        if ( deltaTimestamp > blocksElapsed) {
            return sub_(deltaTimestamp,blocksElapsed);
        }
        return uint(0);
    }

    function getLast24HrsTotalProtocolVolatility() external view returns (uint) {
        return last24HrsTotalProtocolVolatility;
    }

    function getLast24HrsTotalSentimentProtocolVolatility() external view returns (uint) {
        return last24HrsSentimentProtocolVolatility;
    }
    
    function getdeltaBlockslast24HrSession() external view returns (uint) {
        return deltaBlockslast24HrSession;
    }

    function getBlockNumber() public view returns (uint32) {
        return uint32(block.number);
    }
    
    

}