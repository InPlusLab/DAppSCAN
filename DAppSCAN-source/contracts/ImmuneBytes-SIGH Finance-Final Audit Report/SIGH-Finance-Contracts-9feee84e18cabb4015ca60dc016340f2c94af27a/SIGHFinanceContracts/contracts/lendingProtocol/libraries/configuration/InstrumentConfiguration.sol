// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {DataTypes} from '../types/DataTypes.sol';

  /**
  * @title InstrumentConfiguration library
  * @author Aave
  * @notice Implements the bitmap logic to handle the instrument configuration
  */
  library InstrumentConfiguration {

      uint256 constant LTV_MASK =                   0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000; // prettier-ignore
      uint256 constant LIQUIDATION_THRESHOLD_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFF; // prettier-ignore
      uint256 constant LIQUIDATION_BONUS_MASK =     0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFF; // prettier-ignore
      uint256 constant DECIMALS_MASK =              0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFF; // prettier-ignore
      uint256 constant ACTIVE_MASK =                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFF; // prettier-ignore
      uint256 constant FROZEN_MASK =                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFFFFFFFFFFFFFF; // prettier-ignore
      uint256 constant BORROWING_MASK =             0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFBFFFFFFFFFFFFFF; // prettier-ignore
      uint256 constant STABLE_BORROWING_MASK =      0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF7FFFFFFFFFFFFFF; // prettier-ignore
      uint256 constant RESERVE_FACTOR_MASK =        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFF; // prettier-ignore

      /// @dev For the LTV, the start bit is 0 (up to 15), hence no bitshifting is needed
      uint256 constant LIQUIDATION_THRESHOLD_START_BIT_POSITION = 16;
      uint256 constant LIQUIDATION_BONUS_START_BIT_POSITION = 32;
      uint256 constant INSTRUMENT_DECIMALS_START_BIT_POSITION = 48;
      uint256 constant IS_ACTIVE_START_BIT_POSITION = 56;
      uint256 constant IS_FROZEN_START_BIT_POSITION = 57;
      uint256 constant BORROWING_ENABLED_START_BIT_POSITION = 58;
      uint256 constant STABLE_BORROWING_ENABLED_START_BIT_POSITION = 59;
      uint256 constant RESERVE_FACTOR_START_BIT_POSITION = 64;

      uint256 constant MAX_VALID_LTV = 65535;
      uint256 constant MAX_VALID_LIQUIDATION_THRESHOLD = 65535;
      uint256 constant MAX_VALID_LIQUIDATION_BONUS = 65535;
      uint256 constant MAX_VALID_DECIMALS = 255;
      uint256 constant MAX_VALID_RESERVE_FACTOR = 65535;

    /**
    * @dev Sets the Loan to Value of the instrument
    * @param self The instrument configuration
    * @param ltv the new ltv
    **/
    function setLtv(DataTypes.InstrumentConfigurationMap memory self, uint256 ltv) internal pure {
      require(ltv <= MAX_VALID_LTV, "LTV value needs to be less than 65535");

      self.data = (self.data & LTV_MASK) | ltv;
    }

    /**
    * @dev Gets the Loan to Value of the instrument
    * @param self The instrument configuration
    * @return The loan to value
    **/
    function getLtv(DataTypes.InstrumentConfigurationMap storage self) internal view returns (uint256) {
      return self.data & ~LTV_MASK;
    }

    /**
    * @dev Sets the liquidation threshold of the instrument
    * @param self The instrument configuration
    * @param threshold The new liquidation threshold
    **/
    function setLiquidationThreshold(DataTypes.InstrumentConfigurationMap memory self, uint256 threshold) internal pure {
      require(threshold <= MAX_VALID_LIQUIDATION_THRESHOLD, "Liquidation Threshold value needs to be less than 65535");
      self.data = (self.data & LIQUIDATION_THRESHOLD_MASK) | (threshold << LIQUIDATION_THRESHOLD_START_BIT_POSITION);
    }

    /**
    * @dev Gets the liquidation threshold of the instrument
    * @param self The instrument configuration
    * @return The liquidation threshold
    **/
    function getLiquidationThreshold(DataTypes.InstrumentConfigurationMap storage self) internal view returns (uint256) {
      return (self.data & ~LIQUIDATION_THRESHOLD_MASK) >> LIQUIDATION_THRESHOLD_START_BIT_POSITION;
    }

    /**
    * @dev Sets the liquidation bonus of the instrument
    * @param self The instrument configuration
    * @param bonus The new liquidation bonus
    **/
    function setLiquidationBonus(DataTypes.InstrumentConfigurationMap memory self, uint256 bonus) internal pure {
      require(bonus <= MAX_VALID_LIQUIDATION_BONUS, "Liquidation Bonus value needs to be less than 65535");
      self.data = (self.data & LIQUIDATION_BONUS_MASK) | (bonus << LIQUIDATION_BONUS_START_BIT_POSITION);
    }

    /**
    * @dev Gets the liquidation bonus of the instrument
    * @param self The instrument configuration
    * @return The liquidation bonus
    **/
    function getLiquidationBonus(DataTypes.InstrumentConfigurationMap storage self) internal view returns (uint256) {
      return (self.data & ~LIQUIDATION_BONUS_MASK) >> LIQUIDATION_BONUS_START_BIT_POSITION;
    }

    /**
    * @dev Sets the decimals of the underlying asset of the instrument
    * @param self The instrument configuration
    * @param decimals The decimals
    **/
    function setDecimals(DataTypes.InstrumentConfigurationMap memory self, uint256 decimals) internal pure {
      require(decimals <= MAX_VALID_DECIMALS, "Decimals value needs to be less than 255");
      self.data = (self.data & DECIMALS_MASK) | (decimals << INSTRUMENT_DECIMALS_START_BIT_POSITION);
    }

    /**
    * @dev Gets the decimals of the underlying asset of the instrument
    * @param self The instrument configuration
    * @return The decimals of the asset
    **/
    function getDecimals(DataTypes.InstrumentConfigurationMap storage self) internal view returns (uint256) {
      return (self.data & ~DECIMALS_MASK) >> INSTRUMENT_DECIMALS_START_BIT_POSITION;
    }

    /**
    * @dev Sets the active state of the instrument
    * @param self The instrument configuration
    * @param active The active state
    **/
    function setActive(DataTypes.InstrumentConfigurationMap memory self, bool active) internal pure {
      self.data = (self.data & ACTIVE_MASK) | (uint256(active ? 1 : 0) << IS_ACTIVE_START_BIT_POSITION);
    }

    /**
    * @dev Gets the active state of the instrument
    * @param self The instrument configuration
    * @return The active state
    **/
    function getActive(DataTypes.InstrumentConfigurationMap storage self) internal view returns (bool) {
      return (self.data & ~ACTIVE_MASK) != 0;
    }

    /**
    * @dev Sets the frozen state of the instrument
    * @param self The instrument configuration
    * @param frozen The frozen state
    **/
    function setFrozen(DataTypes.InstrumentConfigurationMap memory self, bool frozen) internal pure {
      self.data = (self.data & FROZEN_MASK) | (uint256(frozen ? 1 : 0) << IS_FROZEN_START_BIT_POSITION);
    }

    /**
    * @dev Gets the frozen state of the instrument
    * @param self The instrument configuration
    * @return The frozen state
    **/
    function getFrozen(DataTypes.InstrumentConfigurationMap storage self) internal view returns (bool) {
      return (self.data & ~FROZEN_MASK) != 0;
    }

    /**
    * @dev Enables or disables borrowing on the instrument
    * @param self The instrument configuration
    * @param enabled True if the borrowing needs to be enabled, false otherwise
    **/
    function setBorrowingEnabled(DataTypes.InstrumentConfigurationMap memory self, bool enabled) internal pure {
      self.data = (self.data & BORROWING_MASK) | (uint256(enabled ? 1 : 0) << BORROWING_ENABLED_START_BIT_POSITION);
    }

    /**
    * @dev Gets the borrowing state of the instrument
    * @param self The instrument configuration
    * @return The borrowing state
    **/
    function getBorrowingEnabled(DataTypes.InstrumentConfigurationMap storage self) internal view returns (bool) {
      return (self.data & ~BORROWING_MASK) != 0;
    }

    /**
    * @dev Enables or disables stable rate borrowing on the instrument
    * @param self The instrument configuration
    * @param enabled True if the stable rate borrowing needs to be enabled, false otherwise
    **/
    function setStableRateBorrowingEnabled(DataTypes.InstrumentConfigurationMap memory self, bool enabled) internal  pure {
      self.data =  (self.data & STABLE_BORROWING_MASK) |  (uint256(enabled ? 1 : 0) << STABLE_BORROWING_ENABLED_START_BIT_POSITION);
    }

    /**
    * @dev Gets the stable rate borrowing state of the instrument
    * @param self The instrument configuration
    * @return The stable rate borrowing state
    **/
    function getStableRateBorrowingEnabled(DataTypes.InstrumentConfigurationMap storage self)  internal  view  returns (bool) {
      return (self.data & ~STABLE_BORROWING_MASK) != 0;
    }

    /**
    * @dev Sets the reserve factor of the instrument
    * @param self The instrument configuration
    * @param reserveFactor The reserve factor
    **/
    function setReserveFactor(DataTypes.InstrumentConfigurationMap memory self, uint256 reserveFactor) internal pure {
      require(reserveFactor <= MAX_VALID_RESERVE_FACTOR, "Reserve Factor value not valid. It needs to be less than 65535");
      self.data = (self.data & RESERVE_FACTOR_MASK) | (reserveFactor << RESERVE_FACTOR_START_BIT_POSITION);
    }

    /**
    * @dev Gets the reserve factor of the instrument
    * @param self The instrument configuration
    * @return The reserve factor
    **/
    function getReserveFactor(DataTypes.InstrumentConfigurationMap storage self) internal view returns (uint256) {
      return (self.data & ~RESERVE_FACTOR_MASK) >> RESERVE_FACTOR_START_BIT_POSITION;
    }

    /**
    * @dev Gets the configuration flags of the instrument
    * @param self The instrument configuration
    **/
    function getFlags(DataTypes.InstrumentConfigurationMap storage self)  internal  view  returns (bool isActive,bool isFrozen,bool isBorrowingEnabled ,bool isStableBorrowingEnabled) {
        uint256 dataLocal = self.data;
        isActive = (dataLocal & ~ACTIVE_MASK) != 0;
        isFrozen = (dataLocal & ~FROZEN_MASK) != 0;
        isBorrowingEnabled = (dataLocal & ~BORROWING_MASK) != 0;
        isStableBorrowingEnabled = (dataLocal & ~STABLE_BORROWING_MASK) != 0;
    }

    /**
    * @dev Gets the configuration parameters of the instrument reserve
    * @param self The instrument configuration
    **/
    function getParams(DataTypes.InstrumentConfigurationMap storage self)  internal view  returns ( uint256 ltv,uint256 liquidation_threshold, uint256 liquidation_bonus , uint256 decimals, uint256 reserveFactor) {
      uint256 dataLocal = self.data;
      ltv = dataLocal & ~LTV_MASK;
      liquidation_threshold = (dataLocal & ~LIQUIDATION_THRESHOLD_MASK) >> LIQUIDATION_THRESHOLD_START_BIT_POSITION;
      liquidation_bonus = (dataLocal & ~LIQUIDATION_BONUS_MASK) >> LIQUIDATION_BONUS_START_BIT_POSITION;
      decimals = (dataLocal & ~DECIMALS_MASK) >> INSTRUMENT_DECIMALS_START_BIT_POSITION;
      reserveFactor = (dataLocal & ~RESERVE_FACTOR_MASK) >> RESERVE_FACTOR_START_BIT_POSITION;
    }

    /**
    * @dev Gets the configuration paramters of the instrument from a memory object
    * @param self The instrument configuration
    **/
    function getParamsMemory(DataTypes.InstrumentConfigurationMap memory self)  internal pure returns ( uint256 ltv,uint256 liquidation_threshold, uint256 liquidation_bonus , uint256 decimals, uint256 reserveFactor) {
      ltv = self.data & ~LTV_MASK;
      liquidation_threshold = (self.data & ~LIQUIDATION_THRESHOLD_MASK) >> LIQUIDATION_THRESHOLD_START_BIT_POSITION;
      liquidation_bonus = (self.data & ~LIQUIDATION_BONUS_MASK) >> LIQUIDATION_BONUS_START_BIT_POSITION;
      decimals = (self.data & ~DECIMALS_MASK) >> INSTRUMENT_DECIMALS_START_BIT_POSITION;
      reserveFactor = (self.data & ~RESERVE_FACTOR_MASK) >> RESERVE_FACTOR_START_BIT_POSITION;
    }

    /**
    * @dev Gets the configuration flags of the instrument from a memory object
    * @param self The instrument configuration
    **/
    function getFlagsMemory(DataTypes.InstrumentConfigurationMap memory self) internal pure returns (bool isActive,bool isFrozen,bool isBorrowingEnabled ,bool isStableBorrowingEnabled) {
        isActive = (self.data & ~ACTIVE_MASK) != 0;
        isFrozen = (self.data & ~FROZEN_MASK) != 0;
        isBorrowingEnabled = (self.data & ~BORROWING_MASK) != 0;
        isStableBorrowingEnabled = (self.data & ~STABLE_BORROWING_MASK) != 0;
    }

  }