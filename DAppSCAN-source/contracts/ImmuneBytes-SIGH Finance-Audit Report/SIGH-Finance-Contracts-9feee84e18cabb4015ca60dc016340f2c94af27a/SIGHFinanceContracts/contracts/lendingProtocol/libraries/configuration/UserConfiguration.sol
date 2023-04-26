// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {DataTypes} from '../types/DataTypes.sol';

/**
 * @title UserConfiguration library
 * @author Aave
 * @notice Implements the bitmap logic to handle the user configuration
 */
library UserConfiguration {
  uint256 internal constant BORROWING_MASK = 0x5555555555555555555555555555555555555555555555555555555555555555;

  /**
   * @dev Sets if the user is borrowing the instrument identified by instrumentIndex
   * @param self The configuration object
   * @param instrumentIndex The index of the instrument in the bitmap
   * @param borrowing True if the user is borrowing the instrument, false otherwise
   **/
  function setBorrowing(DataTypes.UserConfigurationMap storage self, uint256 instrumentIndex, bool borrowing) internal {
    require(instrumentIndex < 128,"Invalid instrument Index");
    self.data = (self.data & ~(1 << (instrumentIndex * 2))) | (uint256(borrowing ? 1 : 0) << (instrumentIndex * 2));
  }

  /**
   * @dev Sets if the user is using as collateral the instrument identified by instrumentIndex
   * @param self The configuration object
   * @param instrumentIndex The index of the instrument in the bitmap
   * @param usingAsCollateral True if the user is using the instrument as collateral, false otherwise
   **/
  function setUsingAsCollateral(DataTypes.UserConfigurationMap storage self, uint256 instrumentIndex, bool usingAsCollateral) internal {
    require(instrumentIndex < 128,"Invalid instrument Index");
    self.data = (self.data & ~(1 << (instrumentIndex * 2 + 1))) | (uint256(usingAsCollateral ? 1 : 0) << (instrumentIndex * 2 + 1));
  }

  /**
   * @dev Used to validate if a user has been using the instrument for borrowing or as collateral
   * @param self The configuration object
   * @param instrumentIndex The index of the instrument in the bitmap
   * @return True if the user has been using a instrument for borrowing or as collateral, false otherwise
   **/
  function isUsingAsCollateralOrBorrowing(DataTypes.UserConfigurationMap memory self, uint256 instrumentIndex) internal pure returns (bool) {
    require(instrumentIndex < 128,"Invalid instrument Index");
    return (self.data >> (instrumentIndex * 2)) & 3 != 0;
  }

  /**
   * @dev Used to validate if a user has been using the instrument for borrowing
   * @param self The configuration object
   * @param instrumentIndex The index of the instrument in the bitmap
   * @return True if the user has been using a instrument for borrowing, false otherwise
   **/
  function isBorrowing(DataTypes.UserConfigurationMap memory self, uint256 instrumentIndex) internal pure returns (bool) {
    require(instrumentIndex < 128,"Invalid instrument Index");
    return (self.data >> (instrumentIndex * 2)) & 1 != 0;
  }

  /**
   * @dev Used to validate if a user has been using the instrument as collateral
   * @param self The configuration object
   * @param instrumentIndex The index of the instrument in the bitmap
   * @return True if the user has been using a instrument as collateral, false otherwise
   **/
  function isUsingAsCollateral(DataTypes.UserConfigurationMap memory self, uint256 instrumentIndex) internal pure returns (bool) {
    require(instrumentIndex < 128,"Invalid instrument Index");
    return (self.data >> (instrumentIndex * 2 + 1)) & 1 != 0;
  }

  /**
   * @dev Used to validate if a user has been borrowing from any instrument
   * @param self The configuration object
   * @return True if the user has been borrowing any instrument, false otherwise
   **/
  function isBorrowingAny(DataTypes.UserConfigurationMap memory self) internal pure returns (bool) {
    return self.data & BORROWING_MASK != 0;
  }

  /**
   * @dev Used to validate if a user has not been using any instrument
   * @param self The configuration object
   * @return True if the user has been borrowing any instrument, false otherwise
   **/
  function isEmpty(DataTypes.UserConfigurationMap memory self) internal pure returns (bool) {
    return self.data == 0;
  }
}