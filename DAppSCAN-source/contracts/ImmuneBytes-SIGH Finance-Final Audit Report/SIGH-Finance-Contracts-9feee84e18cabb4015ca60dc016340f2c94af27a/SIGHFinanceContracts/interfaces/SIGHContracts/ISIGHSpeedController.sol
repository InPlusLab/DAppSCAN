// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

/**
 * @title Sigh Speed Controller Contract
 * @notice Distributes a token to a different contract at a fixed rate.
 * @dev This contract must be poked via the `drip()` function every so often.
 * @author _astromartian
 */

interface ISIGHSpeedController {

// #############################################################################################
// ###########   SIGH DISTRIBUTION : INITIALIZED DRIPPING (Can be called only once)   ##########
// #############################################################################################

  function beginDripping () external returns (bool);
  function updateSighVolatilityDistributionSpeed(uint newSpeed) external returns (bool);

// ############################################################################################################
// ###########   SIGH DISTRIBUTION : ADDING / REMOVING NEW PROTOCOL WHICH WILL RECEIVE SIGH TOKENS   ##########
// ############################################################################################################

  function supportNewProtocol( address newProtocolAddress, uint sighSpeedRatio ) external returns (bool);
  function updateProtocolState(address _protocolAddress, bool isSupported_, uint newRatio_) external  returns (bool);

// #####################################################################
// ###########   SIGH DISTRIBUTION FUNCTION - DRIP FUNCTION   ##########
// #####################################################################

  function drip() external ;

// ###############################################################
// ###########   EXTERNAL VIEW functions TO GET STATE   ##########
// ###############################################################

  function getGlobalAddressProvider() external view returns (address);
  function getSighAddress() external view returns (address);
  function getSighVolatilityHarvester() external view returns (address);

  function getSIGHBalance() external view returns (uint);
  function getSIGHVolatilityHarvestingSpeed() external view returns (uint);

  function getSupportedProtocols() external view returns (address[] memory);
  function isThisProtocolSupported(address protocolAddress) external view returns (bool);
  function getSupportedProtocolState(address protocolAddress) external view returns (bool isSupported,
                                                                                    uint sighHarvestingSpeedRatio,
                                                                                    uint totalDrippedAmount,
                                                                                    uint recentlyDrippedAmount );
  function getTotalAmountDistributedToProtocol(address protocolAddress) external view returns (uint);
  function getRecentAmountDistributedToProtocol(address protocolAddress) external view returns (uint);
  function getSIGHSpeedRatioForProtocol(address protocolAddress) external view returns (uint);
  function totalProtocolsSupported() external view returns (uint);

  function _isDripAllowed() external view returns (bool);
  function getlastDripBlockNumber() external view returns (uint);

}