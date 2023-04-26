// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

/**
 * @title Sigh Speed Controller Contract
 * @notice Distributes a token to a different contract at a fixed rate.
 * @dev This contract must be poked via the `drip()` function every so often.
 * @author _astromartian
 */



import {ISIGHVolatilityHarvester} from "../../interfaces/SIGHContracts/ISighVolatilityHarvester.sol";
import {VersionedInitializable} from "../dependencies/upgradability/VersionedInitializable.sol";
import {IGlobalAddressesProvider} from "../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";
import {IERC20} from "../dependencies/openzeppelin/token/ERC20/IERC20.sol";
import {ISIGHSpeedController} from "../../interfaces/SIGHContracts/ISIGHSpeedController.sol";

contract SIGHSpeedController is ISIGHSpeedController, VersionedInitializable  {

  IGlobalAddressesProvider private addressesProvider;

  IERC20 private sighInstrument;                                         // SIGH INSTRUMENT CONTRACT

  bool private isDripAllowed = false;
  uint private lastDripBlockNumber;

   ISIGHVolatilityHarvester private sighVolatilityHarvester;      // SIGH DISTRIBUTION HANDLER CONTRACT
   uint256 private sighVolatilityHarvestingSpeed;
   uint private totalDrippedToVolatilityHarvester;                 // TOTAL $SIGH DRIPPED TO SIGH VOLATILTIY HARVESTER
   uint private recentlyDrippedToVolatilityHarvester;              // $SIGH RECENTLY DRIPPED TO SIGH VOLATILTIY HARVESTER

  struct protocolState {
    bool isSupported;
    Exp sighSpeedRatio;
    uint totalDrippedAmount;
    uint recentlyDrippedAmount;
  }

  address[] private storedSupportedProtocols;
  mapping (address => protocolState) private supportedProtocols;


    struct Exp {
        uint mantissa;
    }

    uint private expScale = 1e18;

// ########################
// ####### EVENTS #########
// ########################

  event DistributionInitialized(address sighVolatilityHarvesterAddress);

  event SighVolatilityHarvestsSpeedUpdated(uint newSIGHDistributionSpeed );

  event NewProtocolSupported (address protocolAddress, uint sighSpeedRatio, uint totalDrippedAmount);
  event ProtocolUpdated(address _protocolAddress, bool _isSupported , uint _sighSpeedRatio);

  event DrippedToVolatilityHarvester(address sighVolatilityHarvesterAddress,uint deltaBlocks,uint harvestDistributionSpeed,uint recentlyDrippedToVolatilityHarvester ,uint totalDrippedToVolatilityHarvester);
  event Dripped(address protocolAddress, uint deltaBlocks, uint sighSpeedRatio, uint distributionSpeed, uint AmountDripped, uint totalAmountDripped);

// ########################
// ####### MODIFIER #######
// ########################

    //only SIGH Finance Configurator can use functions affected by this modifier
    modifier onlySighFinanceConfigurator {
        require(addressesProvider.getSIGHFinanceConfigurator() == msg.sender, "The caller must be SIGH Finance Configurator Contract");
        _;
    }

// ###########################
// ####### CONSTRUCTOR #######
// ###########################

    uint256 public constant REVISION = 0x1;             // NEEDED AS PART OF UPGRADABLE CONTRACTS FUNCTIONALITY ( VersionedInitializable )

    function getRevision() internal override pure returns (uint256) {        // NEEDED AS PART OF UPGRADABLE CONTRACTS FUNCTIONALITY ( VersionedInitializable )
        return REVISION;
    }

    /**
    * @dev this function is invoked by the proxy contract when the LendingPool contract is added to the AddressesProvider.
    * @param _addressesProvider the address of the GlobalAddressesProvider registry
    **/
    function initialize(IGlobalAddressesProvider _addressesProvider) public initializer {
        addressesProvider = _addressesProvider;
        refreshConfigInternal();
    }

  function refreshConfigInternal() internal {
    require(address(addressesProvider) != address(0), " AddressesProvider not initialized Properly ");
    sighInstrument = IERC20(addressesProvider.getSIGHAddress());
    require(address(sighInstrument) != address(0), " SIGH Instrument not initialized Properly ");
  }


// #############################################################################################
// ###########   SIGH DISTRIBUTION : INITIALIZED DRIPPING (Can be called only once)   ##########
// #############################################################################################

  function beginDripping () external override onlySighFinanceConfigurator returns (bool) {
    require(!isDripAllowed,"Dripping can only be initialized once");
    address sighVolatilityHarvesterAddress_ = addressesProvider.getSIGHVolatilityHarvester();
    require(sighVolatilityHarvesterAddress_ != address(0),"SIGH Volatility Harvester Address not valid");

    isDripAllowed = true;
    sighVolatilityHarvester = ISIGHVolatilityHarvester(sighVolatilityHarvesterAddress_);
    lastDripBlockNumber = block.number;

    emit DistributionInitialized( sighVolatilityHarvesterAddress_);
    return true;
  }

  function updateSighVolatilityDistributionSpeed(uint newSpeed) external override onlySighFinanceConfigurator returns (bool) {
    sighVolatilityHarvestingSpeed = newSpeed;
    emit SighVolatilityHarvestsSpeedUpdated( sighVolatilityHarvestingSpeed );
    return true;
  }

// ############################################################################################################
// ###########   SIGH DISTRIBUTION : ADDING / REMOVING NEW PROTOCOL WHICH WILL RECEIVE SIGH INSTRUMENTS   ##########
// ############################################################################################################

  function supportNewProtocol( address newProtocolAddress, uint sighSpeedRatio ) external override onlySighFinanceConfigurator returns (bool)  {
    require (!supportedProtocols[newProtocolAddress].isSupported, 'Already supported');
    require (  sighSpeedRatio == 0 || ( 0.01e18 <= sighSpeedRatio && sighSpeedRatio <= 2e18 ), "Invalid SIGH Speed Ratio");


    if (isDripAllowed) {
        dripInternal();
        dripToVolatilityHarvesterInternal();
        lastDripBlockNumber = block.number;
    }

    if ( supportedProtocols[newProtocolAddress].totalDrippedAmount > 0 ) {
        supportedProtocols[newProtocolAddress].isSupported = true;
        supportedProtocols[newProtocolAddress].sighSpeedRatio = Exp({ mantissa: sighSpeedRatio });
    }
    else {
        storedSupportedProtocols.push(newProtocolAddress);                              // ADDED TO THE LIST
        supportedProtocols[newProtocolAddress] = protocolState({ isSupported: true, sighSpeedRatio: Exp({ mantissa: sighSpeedRatio }), totalDrippedAmount: uint(0), recentlyDrippedAmount: uint(0) });
    }

    require (supportedProtocols[newProtocolAddress].isSupported, 'Error occured when adding the new protocol');
    require (supportedProtocols[newProtocolAddress].sighSpeedRatio.mantissa == sighSpeedRatio, 'Speed Ratio not initialized properly.');

    emit NewProtocolSupported(newProtocolAddress, supportedProtocols[newProtocolAddress].sighSpeedRatio.mantissa, supportedProtocols[newProtocolAddress].totalDrippedAmount);
    return true;
  }

// ######################################################################################
// ###########   SIGH DISTRIBUTION : FUNCTIONS TO UPDATE DISTRIBUTION SPEEDS   ##########
// ######################################################################################

  function updateProtocolState (address _protocolAddress, bool isSupported_, uint newRatio_) external override onlySighFinanceConfigurator returns (bool) {
    require (  newRatio_ == 0 || ( 0.01e18 <= newRatio_ && newRatio_ <= 2e18 ), "Invalid Speed Ratio");
    address[] memory protocols = storedSupportedProtocols;
    bool counter = false;

    for (uint i; i < protocols.length;i++) {
        if ( _protocolAddress == protocols[i] ) {
            counter = true;
            break;
        }
    }
    require(counter,'Protocol not supported');

    if (isDripAllowed) {
        dripInternal();
        dripToVolatilityHarvesterInternal();
        lastDripBlockNumber = block.number;
    }

    supportedProtocols[_protocolAddress].isSupported = isSupported_;
    supportedProtocols[_protocolAddress].sighSpeedRatio.mantissa = newRatio_;
    require(supportedProtocols[_protocolAddress].sighSpeedRatio.mantissa == newRatio_, "SIGH Volatiltiy harvesting - Speed Ratio was not properly updated");

    emit ProtocolUpdated(_protocolAddress, supportedProtocols[_protocolAddress].isSupported , supportedProtocols[_protocolAddress].sighSpeedRatio.mantissa);
    return true;
  }


// #####################################################################
// ###########   SIGH DISTRIBUTION FUNCTION - DRIP FUNCTION   ##########
// #####################################################################

  /**
    * @notice Drips the maximum amount of sighInstruments to match the drip rate since inception
    * @dev Note: this will only drip up to the amount of sighInstruments available.
    */
  function drip() override public {
    require(isDripAllowed,'Dripping has not been initialized by the SIGH Finance Manager');
    dripInternal();
    dripToVolatilityHarvesterInternal();
    lastDripBlockNumber = block.number;
  }

  function dripToVolatilityHarvesterInternal() internal {
    if ( address(sighVolatilityHarvester) == address(0) || lastDripBlockNumber == block.number ) {
      return;
    }

    uint blockNumber_ = block.number;
    uint reservoirBalance_ = sighInstrument.balanceOf(address(this));
    uint deltaBlocks = sub(blockNumber_,lastDripBlockNumber,"Delta Blocks gave error");

    uint deltaDrip_ = mul(sighVolatilityHarvestingSpeed, deltaBlocks , "dripTotal overflow");
    uint toDrip_ = min(reservoirBalance_, deltaDrip_);

    require(reservoirBalance_ != 0, 'Transfer: The reservoir currently does not have any SIGH' );
    require(sighInstrument.transfer(address(sighVolatilityHarvester), toDrip_), 'Protocol Transfer: The transfer did not complete.' );

    totalDrippedToVolatilityHarvester = add(totalDrippedToVolatilityHarvester,toDrip_,"Overflow");
    recentlyDrippedToVolatilityHarvester = toDrip_;

    emit DrippedToVolatilityHarvester( address(sighVolatilityHarvester), deltaBlocks, sighVolatilityHarvestingSpeed, recentlyDrippedToVolatilityHarvester , totalDrippedToVolatilityHarvester);
  }


  function dripInternal() internal {

    if (lastDripBlockNumber == block.number) {
        return;
    }

    address[] memory protocols = storedSupportedProtocols;
    uint length = protocols.length;

    uint currentVolatilityHarvestSpeed = sighVolatilityHarvester.getSIGHSpeedUsed();
    uint reservoirBalance_;

    uint blockNumber_ = block.number;
    uint deltaBlocks = sub(blockNumber_,lastDripBlockNumber,"Delta Blocks gave error");

    if (length > 0 && currentVolatilityHarvestSpeed > 0) {

        for ( uint i=0; i < length; i++) {
            address current_protocol = protocols[i];

            if ( supportedProtocols[ current_protocol ].isSupported ) {

                reservoirBalance_ = sighInstrument.balanceOf(address(this));
                uint distributionSpeed = mul_(currentVolatilityHarvestSpeed, supportedProtocols[current_protocol].sighSpeedRatio );       // current Harvest Speed * Ratio / 1e18
                uint deltaDrip_ = mul(distributionSpeed, deltaBlocks , "dripTotal overflow");
                uint toDrip_ = min(reservoirBalance_, deltaDrip_);

                require(reservoirBalance_ != 0, 'Transfer: The reservoir currently does not have any SIGH Instruments' );
                require(sighInstrument.transfer(current_protocol, toDrip_), 'Transfer: The transfer did not complete.' );

                supportedProtocols[current_protocol].totalDrippedAmount = add(supportedProtocols[current_protocol].totalDrippedAmount , toDrip_,"Overflow");
                supportedProtocols[current_protocol].recentlyDrippedAmount = toDrip_;

                emit Dripped( current_protocol, deltaBlocks, supportedProtocols[ current_protocol ].sighSpeedRatio.mantissa, distributionSpeed , toDrip_ , supportedProtocols[current_protocol].totalDrippedAmount );
            }
        }
    }

  }




// ###############################################################
// ###########   EXTERNAL VIEW functions TO GET STATE   ##########
// ###############################################################

  function getSighAddress() external override view returns (address) {
    return address(sighInstrument);
  }

  function getGlobalAddressProvider() external override view returns (address) {
    return address(addressesProvider);
  }

  function getSighVolatilityHarvester() external override view returns (address) {
    return address(sighVolatilityHarvester);
  }

  function getSIGHVolatilityHarvestingSpeed() external override view returns (uint) {
    return sighVolatilityHarvestingSpeed;
  }

  function getSIGHBalance() external override view returns (uint) {
    uint balance = sighInstrument.balanceOf(address(this));
    return balance;
  }

  function getSupportedProtocols() external override view returns (address[] memory) {
    return storedSupportedProtocols;
  }

  function isThisProtocolSupported(address protocolAddress) external override view returns (bool) {
    if (protocolAddress == address(sighVolatilityHarvester) ) {
        return true;
    }
    return supportedProtocols[protocolAddress].isSupported;
  }

  function getSupportedProtocolState(address protocolAddress) external override view returns (bool isSupported,uint sighHarvestingSpeedRatio,uint totalDrippedAmount,uint recentlyDrippedAmount ) {
    if (protocolAddress == address(sighVolatilityHarvester) ) {
        return (true, 1e18,totalDrippedToVolatilityHarvester,recentlyDrippedToVolatilityHarvester  );
    }

  return (supportedProtocols[protocolAddress].isSupported,
          supportedProtocols[protocolAddress].sighSpeedRatio.mantissa,
          supportedProtocols[protocolAddress].totalDrippedAmount,
          supportedProtocols[protocolAddress].recentlyDrippedAmount  );

  }

  function getTotalAmountDistributedToProtocol(address protocolAddress) external override view returns (uint) {
    if (protocolAddress == address(sighVolatilityHarvester) ) {
        return totalDrippedToVolatilityHarvester;
    }
    return supportedProtocols[protocolAddress].totalDrippedAmount;
  }

  function getRecentAmountDistributedToProtocol(address protocolAddress) external override view returns (uint) {
    if (protocolAddress == address(sighVolatilityHarvester) ) {
        return recentlyDrippedToVolatilityHarvester;
    }
    return supportedProtocols[protocolAddress].recentlyDrippedAmount;
  }

  function getSIGHSpeedRatioForProtocol(address protocolAddress) external override view returns (uint) {
    if (protocolAddress == address(sighVolatilityHarvester) ) {
        return 1e18;
    }
      return supportedProtocols[protocolAddress].sighSpeedRatio.mantissa;
  }

  function totalProtocolsSupported() external override view returns (uint) {
      uint len = storedSupportedProtocols.length;
      return len + 1;
  }


  function _isDripAllowed() external override view returns (bool) {
      return isDripAllowed;
  }

  function getlastDripBlockNumber() external override view returns (uint) {
      return lastDripBlockNumber;
  }

// ###############################################################
// ########### Internal helper functions for safe math ###########
// ###############################################################

  function add(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
    uint c = a + b;
    require(c >= a, errorMessage);
    return c;
  }

  function sub(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
    require(b <= a, errorMessage);
    uint c = a - b;
    return c;
  }

  function mul(uint a, uint b, string memory errorMessage) internal pure returns (uint) {
    if (a == 0) {
      return 0;
    }
    uint c = a * b;
    require(c / a == b, errorMessage);
    return c;
  }

  function mul_(uint a, Exp memory b) internal view  returns (uint) {
      return mul(a, b.mantissa,'Exp multiplication failed') / expScale;
  }


  function min(uint a, uint b) internal pure returns (uint) {
    if (a <= b) {
      return a;
    } else {
      return b;
    }
  }
}