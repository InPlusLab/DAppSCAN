// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {WadRayMath} from '../libraries/math/WadRayMath.sol';
import {DebtTokenBase} from './base/DebtTokenBase.sol';
import {IVariableDebtToken} from "../../../interfaces/lendingProtocol/IVariableDebtToken.sol";
import {ISIGHHarvester} from "../../../interfaces/lendingProtocol/ISIGHHarvester.sol";

/**
 * @title VariableDebtToken
 * @notice Implements a variable debt token to track the borrowing positions of users
 * at variable rate mode
 * @author Aave
 **/
contract VariableDebtToken is DebtTokenBase, IVariableDebtToken {
  using WadRayMath for uint256;

  uint256 public constant DEBT_TOKEN_REVISION = 0x1;

  constructor(address addressesProvider,address pool, address underlyingAsset, string memory name, string memory symbol) DebtTokenBase(addressesProvider,pool, underlyingAsset, name, symbol) {}

  /**
   * @dev Gets the revision of the stable debt token implementation
   * @return The debt token implementation revision
   **/
  function getRevision() internal pure virtual override returns (uint256) {
    return DEBT_TOKEN_REVISION;
  }

  //  ####################################################
//  ######### FUNCTIONS CALLED BY LENDING POOL #########
//  ####################################################

  /**
   * @dev Mints debt token to the `onBehalfOf` address
   * -  Only callable by the LendingPool
   * @param user The address receiving the borrowed underlying, being the delegatee in case
   * of credit delegate, or same as `onBehalfOf` otherwise
   * @param onBehalfOf The address receiving the debt tokens
   * @param amount The amount of debt being minted
   * @param index The variable debt index of the reserve
   * @return `true` if the the previous balance of the user is 0
   **/
  function mint(address user, address onBehalfOf, uint256 amount, uint256 index) external override onlyLendingPool returns (bool) {
    if (user != onBehalfOf) {
      _decreaseBorrowAllowance(onBehalfOf, user, amount);
    }

    uint256 previousBalance = super.balanceOf(onBehalfOf);
    uint256 amountScaled = amount.rayDiv(index);
    require(amountScaled != 0, "INVALID MINT AMOUNT");

    sighHarvester.accureSIGHForBorrowingStream(user);
    _mint(onBehalfOf, amountScaled);

    emit Transfer(address(0), onBehalfOf, amount);
    emit Mint(user, onBehalfOf, amount, index);

    return previousBalance == 0;
  }

  /**
   * @dev Burns user variable debt
   * - Only callable by the LendingPool
   * @param user The user whose debt is getting burned
   * @param amount The amount getting burned
   * @param index The variable debt index of the reserve
   **/
  function burn(address user, uint256 amount, uint256 index) external override onlyLendingPool {
    uint256 amountScaled = amount.rayDiv(index);
    require(amountScaled != 0, "INVALID BURN AMOUNT");

    sighHarvester.accureSIGHForBorrowingStream(user);
    _burn(user, amountScaled);

    emit Transfer(user, address(0), amount);
    emit Burn(user, amount, index);
  }


//  ##################################
//  ######### VIEW FUNCTIONS #########
//  ##################################

  /**
   * @dev Calculates the accumulated debt balance of the user
   * @return The debt balance of the user
   **/
  function balanceOf(address user) public view virtual override returns (uint256) {
    uint256 scaledBalance = super.balanceOf(user);

    if (scaledBalance == 0) {
      return 0;
    }

    return scaledBalance.rayMul(POOL.getInstrumentNormalizedVariableDebt(UNDERLYING_ASSET_ADDRESS));
  }

  /**
   * @dev Returns the principal debt balance of the user from
   * @return The debt balance of the user since the last burn/mint action
   **/
  function scaledBalanceOf(address user) public view virtual override returns (uint256) {
    return super.balanceOf(user);
  }

  /**
   * @dev Returns the total supply of the variable debt token. Represents the total debt accrued by the users
   * @return The total supply
   **/
  function totalSupply() public view virtual override returns (uint256) {
    return super.totalSupply().rayMul(POOL.getInstrumentNormalizedVariableDebt(UNDERLYING_ASSET_ADDRESS));
  }

  /**
   * @dev Returns the scaled total supply of the variable debt token. Represents sum(debt/index)
   * @return the scaled total supply
   **/
  function scaledTotalSupply() public view virtual override returns (uint256) {
    return super.totalSupply();
  }

  /**
   * @dev Returns the principal balance of the user and principal total supply.
   * @param user The address of the user
   * @return The principal balance of the user
   * @return The principal total supply
   **/
  function getScaledUserBalanceAndSupply(address user) external view override returns (uint256, uint256){
    return (super.balanceOf(user), super.totalSupply());
  }

  function averageBalanceOf(address account) public override view returns (uint256) {
    return _averageBalanceOf(account);
  }


}