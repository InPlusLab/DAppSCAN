// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "openzeppelin-solidity/contracts/utils/Context.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @author vigan.abd
 * @title ThriveCoin Vesting Schedule
 *
 * @dev Implementation of the THRIVE Vesting Contract.
 *
 * ThriveCoin Vesting schedule contract is a generic smart contract that
 * provides locking and vesting calculation for single wallet.
 *
 * Vesting schedule is realized through allocating funds for stakeholder for
 * agreed vesting/locking schedule. The contract acts as a wallet for
 * stakeholder and they can withdraw funds once they become available
 * (see calcVestedAmount method). Funds become available periodically and the
 * stakeholder can check these details at any time by accessing the methods like
 * vested or available.
 *
 * NOTE: funds are sent to contract after instantiation!
 *
 * Implementation is based on these two smart contracts:
 * - https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.5/contracts/finance/VestingWallet.sol
 * - https://github.com/cpu-coin/CPUcoin/blob/master/contracts/IERC20Vestable.sol
 *
 * NOTE: extends openzeppelin v4.3.2 contracts:
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.2/contracts/utils/Context.sol
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.2/contracts/token/ERC20/utils/SafeERC20.sol
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.3.2/contracts/access/Ownable.sol
 */
contract ThriveCoinVestingSchedule is Context, Ownable {
  /**
   * @dev Events related to vesting contract
   */
  event VestingFundsClaimed(address indexed token, address indexed beneficiary, uint256 amount);
  event VestingFundsRevoked(
    address indexed token,
    address indexed beneficiary,
    address indexed refundDest,
    uint256 amount
  );
  event VestingBeneficiaryChanged(
    address indexed token,
    address indexed oldBeneficiary,
    address indexed newBeneficiary
  );

  /**
   * @dev Throws if called by any account other than the beneficiary.
   */
  modifier onlyBeneficiary() {
    require(beneficiary() == _msgSender(), "ThriveCoinVestingSchedule: only beneficiary can perform the action");
    _;
  }

  /**
   * @dev Throws if contract is revoked.
   */
  modifier notRevoked() {
    require(revoked() == false, "ThriveCoinVestingSchedule: contract is revoked");
    _;
  }

  uint256 private constant SECONDS_PER_DAY = 86400;

  /**
   * @dev ERC20 token address
   */
  address private immutable _token;

  /**
   * @dev Beneficiary address that is able to claim funds
   */
  address private _beneficiary;

  /**
   * @dev Total allocated amount
   */
  uint256 private _allocatedAmount;

  /**
   * @dev Start day of the vesting schedule
   */
  uint256 private _startDay;

  /**
   * @dev Vesting schedule duration in days
   */
  uint256 private _duration;

  /**
   * @dev Vesting schedule cliff period in days
   */
  uint256 private _cliffDuration;

  /**
   * @dev Vesting schedule unlock period/interval in days
   */
  uint256 private _interval;

  /**
   * @dev Flag that specifies if vesting schedule can be revoked
   */
  bool private immutable _revocable;

  /**
   * @dev Flag that specifies if vesting schedule is revoked
   */
  bool private _revoked;

  /**
   * @dev Flag that specifies if beneficiary can be changed
   */
  bool private immutable _immutableBeneficiary;

  /**
   * @dev Claimed amount so far
   */
  uint256 private _claimed;

  /**
   * @dev Daily claim limit
   */
  uint256 private _claimLimit;

  /**
   * @dev Last time (day) when funds were claimed
   */
  uint256 private _lastClaimedDay;

  /**
   * @dev Amount claimed so far during the day
   */
  uint256 private _dailyClaimedAmount;

  /**
   * @dev Initializes the vesting contract
   *
   * @param token_ - Specifies the ERC20 token that is stored in smart contract
   * @param beneficiary_ - The address that is able to claim funds
   * @param allocatedAmount_ - Specifies the total allocated amount for
   * vesting/locking schedule/period
   * @param startTime - Specifies vesting/locking schedule start day, can be a
   * date in future or past. The vesting schedule will calculate the available
   * amount for claiming (unlocked amount) based on this timestamp.
   * @param duration_ - Specifies the duration in days for vesting/locking
   * schedule. At the point in time where start time + duration is passed the
   * whole funds will be unlocked and the vesting/locking schedule would be
   * finished.
   * @param cliffDuration_ - Specifies the cliff period in days for schedule.
   * Until this point in time is reached funds can’t be claimed, and once this
   * time is passed some portion of funds will be unlocked based on schedule
   * calculation from `startTime`.
   * @param interval_ - Specifies how often the funds will be unlocked (in days).
   * e.g. if this one is 365 it means that funds get unlocked every year.
   * @param claimed_ - Is applicable only if the contract is migrated and
   * specifies the amount claimed so far. In most cases this is 0.
   * @param claimLimit_ - Specifies maximum amount that can be claimed/withdrawn
   * during the day
   * @param revocable_ - Specifies if the smart contract is revocable or not.
   * Once contract is revoked then no more funds can be claimed
   * @param immutableBeneficiary_ - Specifies whenever contract beneficiary can
   * be changed or not. Usually this one is enabled just in case if stakeholder
   * loses access to private key so in this case contract can change account for
   * claiming future funds.
   */
  constructor(
    address token_,
    address beneficiary_,
    uint256 allocatedAmount_,
    uint256 startTime, // unix epoch ms
    uint256 duration_, // in days
    uint256 cliffDuration_, // in days
    uint256 interval_, // in days
    uint256 claimed_, // already claimed, helpful for chain migrations
    uint256 claimLimit_,
    bool revocable_,
    bool immutableBeneficiary_
  ) {
    require(token_ != address(0), "ThriveCoinVestingSchedule: token is zero address");
    require(beneficiary_ != address(0), "ThriveCoinVestingSchedule: beneficiary is zero address");
    require(cliffDuration_ <= duration_, "ThriveCoinVestingSchedule: cliff duration greater than duration");
    require(interval_ >= 1, "ThriveCoinVestingSchedule: interval should be at least 1 day");

    _token = token_;
    _beneficiary = beneficiary_;
    _allocatedAmount = allocatedAmount_;
    _startDay = startTime / SECONDS_PER_DAY;
    _duration = duration_;
    _cliffDuration = cliffDuration_;
    _interval = interval_;
    _claimed = claimed_;
    _claimLimit = claimLimit_;
    _revocable = revocable_;
    _immutableBeneficiary = immutableBeneficiary_;
    _revoked = false;
  }

  /**
   * @dev Returns the address of ERC20 token.
   *
   * @return address
   */
  function token() public view virtual returns (address) {
    return _token;
  }

  /**
   * @dev Returns the address of the current beneficiary.
   *
   * @return address
   */
  function beneficiary() public view virtual returns (address) {
    return _beneficiary;
  }

  /**
   * @dev Returns the total amount allocated for vesting.
   *
   * @return uint256
   */
  function allocatedAmount() public view virtual returns (uint256) {
    return _allocatedAmount;
  }

  /**
   * @dev Returns the start day of the vesting schedule.
   *
   * NOTE: The result is returned in days of year, if you want to get the date
   * you should multiply result with 86400 (seconds for day)
   *
   * @return uint256
   */
  function startDay() public view virtual returns (uint256) {
    return _startDay;
  }

  /**
   * @dev Returns the vesting schedule duration in days unit.
   *
   * @return uint256
   */
  function duration() public view virtual returns (uint256) {
    return _duration;
  }

  /**
   * @dev Returns the vesting schedule cliff duration in days unit.
   *
   * @return uint256
   */
  function cliffDuration() public view virtual returns (uint256) {
    return _cliffDuration;
  }

  /**
   * @dev Returns interval in days of how often funds will be unlocked.
   *
   * @return uint256
   */
  function interval() public view virtual returns (uint256) {
    return _interval;
  }

  /**
   * @dev Returns the flag specifying if the contract is revocable.
   *
   * @return bool
   */
  function revocable() public view virtual returns (bool) {
    return _revocable;
  }

  /**
   * @dev Returns the flag specifying if the beneficiary can be changed after
   * contract instantiation.
   *
   * @return bool
   */
  function immutableBeneficiary() public view virtual returns (bool) {
    return _immutableBeneficiary;
  }

  /**
   * @dev Returns the amount claimed/withdrawn from contract so far.
   *
   * @return uint256
   */
  function claimed() public view virtual returns (uint256) {
    return _claimed;
  }

  /**
   * @dev Returns the amount unlocked so far.
   *
   * @return uint256
   */
  function vested() public view virtual returns (uint256) {
    return calcVestedAmount(block.timestamp);
  }

  /**
   * @dev Returns the amount that is available for claiming/withdrawing.
   *
   * @return uint256
   */
  function available() public view virtual returns (uint256) {
    return calcVestedAmount(block.timestamp) - claimed();
  }

  /**
   * @dev Returns the remaining locked amount
   *
   * @return uint256
   */
  function locked() public view virtual returns (uint256) {
    return allocatedAmount() - calcVestedAmount(block.timestamp);
  }

  /**
   * @dev Returns the flag that specifies if contract is revoked or not.
   *
   * @return bool
   */
  function revoked() public view virtual returns (bool) {
    return _revoked;
  }

  /**
   * @dev Returns the flag specifying that the contract is ready to be used.
   * The function returns true only if the contract has enough balance for
   * transferring total allocated amount - already claimed amount
   */
  function ready() public view virtual returns (bool) {
    uint256 bal = IERC20(_token).balanceOf(address(this));
    return bal >= _allocatedAmount - _claimed;
  }

  /**
   * @dev Calculates vested amount until specified timestamp.
   *
   * @param timestamp - Unix epoch time in seconds
   * @return uint256
   */
  function calcVestedAmount(uint256 timestamp) public view virtual returns (uint256) {
    uint256 start = startDay();
    uint256 length = duration();
    uint256 timestampInDays = timestamp / SECONDS_PER_DAY;
    uint256 totalAmount = allocatedAmount();

    if (timestampInDays < start + cliffDuration()) {
      return 0;
    }

    if (timestampInDays > start + length) {
      return totalAmount;
    }

    uint256 itv = interval();
    uint256 daysVested = timestampInDays - start;
    uint256 effectiveDaysVested = (daysVested / itv) * itv; // e.g. 303/4 => 300, 304/4 => 304

    return (totalAmount * effectiveDaysVested) / length;
  }

  /**
   * @dev Withdraws funds from smart contract to beneficiary. Withdrawal is
   * allowed only if amount is less or equal to available amount and daily limit
   * is zero or greater/equal to amount.
   *
   * @param amount - Amount that will be claimed by beneficiary
   */
  function claim(uint256 amount) public virtual onlyBeneficiary notRevoked {
    require(ready(), "ThriveCoinVestingSchedule: Contract is not fully initialized yet");

    uint256 availableBal = available();
    require(amount <= availableBal, "ThriveCoinVestingSchedule: amount exceeds available balance");

    uint256 limit = claimLimit();
    uint256 timestampInDays = block.timestamp / SECONDS_PER_DAY;
    if (_lastClaimedDay != timestampInDays) {
      _lastClaimedDay = timestampInDays;
      _dailyClaimedAmount = 0;
    }

    require(
      (amount + _dailyClaimedAmount) <= limit || limit == 0,
      "ThriveCoinVestingSchedule: amount exceeds claim limit"
    );

    _dailyClaimedAmount += amount;
    _claimed += amount;
    emit VestingFundsClaimed(_token, _beneficiary, amount);
    SafeERC20.safeTransfer(IERC20(_token), _beneficiary, amount);
  }

  /**
   * @dev Revokes the contract. After revoking no more funds can be claimed and
   * remaining amount is transferred back to contract owner
   */
  function revoke() public virtual onlyOwner notRevoked {
    require(ready(), "ThriveCoinVestingSchedule: Contract is not fully initialized yet");
    require(revocable(), "ThriveCoinVestingSchedule: contract is not revocable");

    uint256 contractBal = IERC20(_token).balanceOf(address(this));
    uint256 amount = allocatedAmount() - claimed();
    address dest = owner();
    _revoked = true;
    emit VestingFundsRevoked(_token, _beneficiary, dest, amount);
    SafeERC20.safeTransfer(IERC20(_token), dest, contractBal);
  }

  /**
   * @dev Changes the address of beneficiary. Once changed only new beneficiary
   * can claim the funds
   *
   * @param newBeneficiary - New beneficiary address that can claim funds from
   * now on
   */
  function changeBeneficiary(address newBeneficiary) public virtual onlyOwner {
    require(immutableBeneficiary() == false, "ThriveCoinVestingSchedule: beneficiary is immutable");

    emit VestingBeneficiaryChanged(_token, _beneficiary, newBeneficiary);
    _beneficiary = newBeneficiary;
  }

  /**
   * @dev Returns the max daily claimable amount.
   *
   * @return uint256
   */
  function claimLimit() public view virtual returns (uint256) {
    return _claimLimit;
  }

  /**
   * @dev Changes daily claim limit.
   *
   * @param newClaimLimit - New daily claim limit
   */
  function changeClaimLimit(uint256 newClaimLimit) public virtual onlyOwner {
    _claimLimit = newClaimLimit;
  }

  /**
   * @dev Returns the day when funds were claimed lastly.
   *
   * @return uint256
   */
  function lastClaimedDay() public view virtual returns (uint256) {
    return _lastClaimedDay;
  }

  /**
   * @dev Returns the amount claimed so far during the day.
   *
   * @return uint256
   */
  function dailyClaimedAmount() public view virtual returns (uint256) {
    uint256 timestampInDays = block.timestamp / SECONDS_PER_DAY;
    return timestampInDays == _lastClaimedDay ? _dailyClaimedAmount : 0;
  }
}
