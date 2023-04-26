// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

/**
 * @title Errors library
 * @author Aave
 * @notice Defines the error messages emitted by the different contracts of the Aave protocol
 * @dev Error messages prefix glossary:
 *  - VL = ValidationLogic
 *  - MATH = Math libraries
 *  - CT = Common errors between tokens (AToken, VariableDebtToken and StableDebtToken)
 *  - AT = AToken
 *  - SDT = StableDebtToken
 *  - VDT = VariableDebtToken
 *  - LP = LendingPool
 *  - LPAPR = LendingPoolAddressesProviderRegistry
 *  - LPC = LendingPoolConfiguration
 *  - RL = ReserveLogic
 *  - LPCM = LendingPoolCollateralManager
 *  - P = Pausable
 */
library Errors {
  //common errors

  string public constant MAX_INST_LIMIT = '1';
  string public constant PAUSED = '2';
  string public constant FAILED = '3';
  string public constant INVALID_RETURN = '4';
  string public constant NOT_ALLOWED = '5';
  string public constant NOT_CONTRACT = '6';
  string public constant VOL_HAR_INIT_FAIL = '7';
  string public constant IT_INIT_FAIL = '8';
  string public constant VT_INIT_FAIL = '9';
  string public constant ST_INIT_FAIL = '10';

  string public constant Already_Supported = '11';
  string public constant LR_INVALID = '12';
  string public constant SR_INVALID = '13';
  string public constant VR_INVALID = '14';

  string public constant CLI_OVRFLW = '15';
  string public constant LI_OVRFLW = '16';
  string public constant VI_OVRFLW = '17';  
  string public constant LIQUIDITY_NOT_AVAILABLE = '18'; 
  string public constant INCONCISTENT_BALANCE = '20'; 



  string public constant CALLER_NOT_POOL_ADMIN = '33'; // 'The caller must be the pool admin'
  string public constant BORROW_ALLOWANCE_NOT_ENOUGH = '59'; // User borrows on behalf, but allowance are too small

  //contract specific errors
  string public constant LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD = '42'; // 'Health factor is not below the threshold'
  string public constant LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED = '43'; // 'The collateral chosen cannot be liquidated'
  string public constant LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER = '44'; // 'User did not borrow the specified currency'
  string public constant LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE = '45'; // "There isn't enough liquidity available to liquidate"
  string public constant LPCM_NO_ERRORS = '46'; // 'No errors'

  enum CollateralManagerErrors {
    NO_ERROR,
    NO_COLLATERAL_AVAILABLE,
    COLLATERAL_CANNOT_BE_LIQUIDATED,
    CURRRENCY_NOT_BORROWED,
    HEALTH_FACTOR_ABOVE_THRESHOLD,
    NOT_ENOUGH_LIQUIDITY,
    NO_ACTIVE_INSTRUMENT,
    HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD,
    INVALID_EQUAL_ASSETS_TO_SWAP,
    FROZEN_INSTRUMENT
  }

}