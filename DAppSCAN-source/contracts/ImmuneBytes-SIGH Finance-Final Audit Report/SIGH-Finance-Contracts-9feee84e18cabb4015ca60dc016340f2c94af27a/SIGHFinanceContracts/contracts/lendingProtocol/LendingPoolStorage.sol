// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {IGlobalAddressesProvider} from "../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";
import {UserConfiguration} from './libraries/configuration/UserConfiguration.sol';
import {InstrumentConfiguration} from './libraries/configuration/InstrumentConfiguration.sol';
import {DataTypes} from './libraries/types/DataTypes.sol';

import {InstrumentReserveLogic} from './libraries/logic/InstrumentReserveLogic.sol';

contract LendingPoolStorage {

  using InstrumentReserveLogic for DataTypes.InstrumentData;
  using InstrumentConfiguration for DataTypes.InstrumentConfigurationMap;
  using UserConfiguration for DataTypes.UserConfigurationMap;

  IGlobalAddressesProvider internal addressesProvider;
  address internal feeProvider;

  address internal sighPayAggregator;
  address internal platformFeeCollector;

  mapping(address => DataTypes.InstrumentData) internal _instruments;
  mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;

  mapping(uint256 => address) internal _instrumentsList;    // the list of the available instruments, structured as a mapping for gas savings reasons
  uint256 internal _instrumentsCount;

  bool internal _paused;
}