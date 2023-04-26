// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {IGlobalAddressesProvider} from "../../../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";
import {IncentivizedERC20} from '../IncentivizedERC20.sol';
import {ILendingPool} from "../../../../interfaces/lendingProtocol/ILendingPool.sol";
import {VersionedInitializable} from "../../../dependencies/upgradability/VersionedInitializable.sol";
import {ICreditDelegationToken} from "../../../../interfaces/lendingProtocol/ICreditDelegationToken.sol";
import {ISIGHHarvester} from "../../../../interfaces/lendingProtocol/ISIGHHarvester.sol";
import {ISIGHHarvestDebtToken} from "../../../../interfaces/lendingProtocol/ISIGHHarvestDebtToken.sol";
import {SafeMath} from "../../../dependencies/openzeppelin/math/SafeMath.sol";


/**
 * @title DebtTokenBase g
 * @notice Base contract for different types of debt tokens, like StableDebtToken or VariableDebtToken
 * @author Aave
 */

abstract contract DebtTokenBase is ISIGHHarvestDebtToken, IncentivizedERC20, VersionedInitializable, ICreditDelegationToken {

  using SafeMath for uint256;

  address public immutable UNDERLYING_ASSET_ADDRESS;
  ILendingPool public immutable POOL;
  IGlobalAddressesProvider public immutable ADDRESSES_PROVIDER;
  ISIGHHarvester public sighHarvester;

  mapping(address => mapping(address => uint256)) internal _borrowAllowances;

  /**
   * @dev Only lending pool can call functions marked by this modifier
   **/
  modifier onlyLendingPool {
    require(_msgSender() == address(POOL), "CALLER MUST BE LENDING POOL");
    _;
  }

  /**
   * @dev The metadata of the token will be set on the proxy, that the reason of
   * passing "NULL" and 0 as metadata
   */
  constructor(address addressesProvider, address pool, address underlyingAssetAddress, string memory name, string memory symbol) IncentivizedERC20(name, symbol, 18) {
    POOL = ILendingPool(pool);
    ADDRESSES_PROVIDER = IGlobalAddressesProvider(addressesProvider);
    UNDERLYING_ASSET_ADDRESS = underlyingAssetAddress;
  }

  /**
   * @dev Initializes the debt token.
   * @param name The name of the token
   * @param symbol The symbol of the token
   * @param decimals The decimals of the token
   */
  function initialize(uint8 decimals, string memory name, string memory symbol) public initializer {
    _setName(name);
    _setSymbol(symbol);
    _setDecimals(decimals);
  }

  /**
   * @dev delegates borrowing power to a user on the specific debt token
   * @param delegatee the address receiving the delegated borrowing power
   * @param amount the maximum amount being delegated. Delegation will still
   * respect the liquidation constraints (even if delegated, a delegatee cannot
   * force a delegator HF to go below 1)
   **/
  function approveDelegation(address delegatee, uint256 amount) external override {
    _borrowAllowances[_msgSender()][delegatee] = amount;
    emit BorrowAllowanceDelegated(_msgSender(), delegatee, UNDERLYING_ASSET_ADDRESS, amount);
  }

  /**
   * @dev returns the borrow allowance of the user
   * @param fromUser The user to giving allowance
   * @param toUser The user to give allowance to
   * @return the current allowance of toUser
   **/
  function borrowAllowance(address fromUser, address toUser) external view override returns (uint256) {
    return _borrowAllowances[fromUser][toUser];
  }

  function _decreaseBorrowAllowance(address delegator, address delegatee, uint256 amount) internal {
    uint256 newAllowance = _borrowAllowances[delegator][delegatee].sub(amount, "BORROW ALLOWANCE NOT ENOUGH");
    _borrowAllowances[delegator][delegatee] = newAllowance;
    emit BorrowAllowanceDelegated(delegator, delegatee, UNDERLYING_ASSET_ADDRESS, newAllowance);
  }

  /**
   * @dev Being non transferrable, the debt token does not implement any of the
   * standard ERC20 functions for transfer and allowance.
   **/
  function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
      recipient; amount;
      revert('TRANSFER_NOT_SUPPORTED');
  }

  function allowance(address owner, address spender) public view virtual override returns (uint256){
    owner; spender;
    revert('ALLOWANCE_NOT_SUPPORTED');
  }

  function approve(address spender, uint256 amount) public virtual override returns (bool) {
    spender; amount;
    revert('APPROVAL_NOT_SUPPORTED');
  }

  function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
    sender; recipient; amount;
    revert('TRANSFER_NOT_SUPPORTED');
  }

  function increaseAllowance(address spender, uint256 addedValue) public virtual override returns (bool) {
    spender; addedValue;
    revert('ALLOWANCE_NOT_SUPPORTED');
  }

  function decreaseAllowance(address spender, uint256 subtractedValue) public virtual override returns (bool) {
    spender;
    subtractedValue;
    revert('ALLOWANCE_NOT_SUPPORTED');
  }

//  ########################################################
//  ######### FUNCTIONS RELATED TO SIGH HARVESTING #########
//  ########################################################

    /**
   * @dev Sets the SIGH Harvester Proxy Contract Address
   * @param _SIGHHarvesterAddress The SIGH Harvester Proxy Contract Address
   * @return The amount transferred
   **/
  function setSIGHHarvesterAddress(address _SIGHHarvesterAddress) external override returns (bool) {
    require(ADDRESSES_PROVIDER.getLendingPoolConfigurator() == msg.sender,'ONLY LP CONFIGURATOR');
    sighHarvester = ISIGHHarvester(_SIGHHarvesterAddress);
    return true;
  }

  function claimSIGH(address[] memory users) public override {
    return sighHarvester.claimSIGH(users);
  }

  function claimMySIGH() public override {
    return sighHarvester.claimMySIGH(msg.sender);
  }

  function getSighAccured(address user)  external view override returns (uint)  {
    return sighHarvester.getSighAccured(user);
  }

//  ############################################
//  ######### FUNCTIONS RELATED TO FEE #########
//  ############################################

  function updatePlatformFee(address user, uint platformFeeIncrease, uint platformFeeDecrease) external onlyLendingPool override {
    sighHarvester.updatePlatformFee(user,platformFeeIncrease,platformFeeDecrease);
  }

  function updateReserveFee(address user, uint reserveFeeIncrease, uint reserveFeeDecrease) external onlyLendingPool override {
    sighHarvester.updateReserveFee(user,reserveFeeIncrease,reserveFeeDecrease);
  }

  function getPlatformFee(address user) external view override returns (uint) {
    return sighHarvester.getPlatformFee(user);
  }

  function getReserveFee(address user)  external view override returns (uint) {
    return sighHarvester.getReserveFee(user);
  }

}