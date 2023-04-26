// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../ProxyClones/OwnableForClones.sol";

// Flexible Vesting Schedule with easy Snapshot compatibility

contract DACVesting is OwnableForClones {

  IERC20 public token;
  
  // Blocktime when the release schedule starts
  uint256 public startTime;

  //everything is released once blocktime >= startTime + duration
  uint256 public duration;

  // 1= linear; 2 = quadratic etc.
  uint256 public exp;

  // cliff: 100 = 1%;
  uint256 public cliff;
  
  // indicates how much earlier than startTime the cliff amount gets released
  uint256 public cliffDelay;

  // maps what each user has deposited total / gotten back out total; Deposit>=Drained at all times
  mapping(address => uint256) private totalDeposit;
  mapping(address => uint256) private drainedAmount;

  event TokensDeposited(address indexed beneficiary, uint256 indexed amount);
  event TokensRetrieved(address indexed beneficiary, uint256 indexed amount);
  event VestingDecreased(address indexed beneficiary, uint256 indexed amount);

  /**
   * @notice initializes the contract, with all parameters set at once
   * @param _token the only token contract that is accepted in this vesting instance
   * @param _owner the owner that can call decreaseVesting, set address(0) to have no owner
   * @param _cliffInTenThousands amount of tokens to be released ahead of startTime: 10000 => 100%
   * @param _cliffDelayInDays the cliff can be retrieved this many days before StartTime of the schedule
   * @param _exp this sets the pace of the schedule. 0 is instant, 1 is linear over time, 2 is quadratic over time etc.
   */
  function initialize
   (
    address _token,
    address _owner,
    uint256 _startInDays,
    uint256 _durationInDays,
    uint256 _cliffInTenThousands,
    uint256 _cliffDelayInDays,
    uint256 _exp
   )
    external initializer
   {
    __Ownable_init();
    token = IERC20(_token);
    startTime = block.timestamp + _startInDays * 86400;
    duration = _durationInDays * 86400;
    cliff = _cliffInTenThousands;
    cliffDelay = _cliffDelayInDays * 86400;
    exp = _exp;
    if (_owner == address(0)) {
      renounceOwnership();
    }else {
      transferOwnership(_owner);
    }
  }

  /**
  * @notice same as depositFor but with memory array as input for gas savings
  */
  function depositForCrowd(address[] memory _recipient, uint256[] memory _amount) external {
    require(_recipient.length == _amount.length, "lengths must match");
    for (uint256 i = 0; i < _recipient.length; i++) {
      _rawDeposit(msg.sender, _recipient[i], _amount[i]);    
    }
  }

  /**
  * @notice sender can deposit tokens for someone else
  * @param _recipient the use to deposit for 
  * @param _amount the amount of tokens to deposit with all decimals
  */
  function depositFor(address _recipient, uint256 _amount) external {
    _rawDeposit(msg.sender, _recipient, _amount);
  }

  /**
  * @notice deposits the amount owned by _recipient from sender for _recipient into this contract
  * @param _recipient the address the funds are vested for
  * @dev only useful in specific contexts like having to burn a wallet and deposit it back in the vesting contract e.g.
  */
  function depositAllFor(address _recipient) external {
    _rawDeposit(msg.sender, _recipient, token.balanceOf(_recipient));
  }

  /**
  * @notice user method to retrieve all that is retrievable
  * @notice reverts when there is nothing to retrieve to save gas
  */
  function retrieve() external {
    uint256 amount = getRetrievableAmount(msg.sender);
    require(amount != 0, "nothing to retrieve");
    _rawRetrieve(msg.sender, amount);
  }

  /**
  * @notice retrieve for an array of addresses at once, useful if users are unable to use the retrieve method or to save gas with mass retrieves
  * @dev does NOT revert when one of the accounts has nothing to retrieve
  */
  function retrieveFor(address[] memory accounts) external {
    for (uint256 i = 0; i < accounts.length; i++) {
      uint256 amount = getRetrievableAmount(accounts[i]);
      _rawRetrieve(accounts[i], amount);
    }
  }

  /**
  * @notice if the ownership got renounced (owner == 0), then this function is uncallable and the vesting is trustless for benificiary
  * @dev only callable by the owner of this instance
  * @dev amount will be stuck in the contract and effectively burned
  */
  function decreaseVesting(address _account, uint256 amount) external onlyOwner {
    require(drainedAmount[_account] <= totalDeposit[_account] - amount, "deposit has to be >= drainedAmount");
    totalDeposit[_account] -= amount;
    emit VestingDecreased(_account, amount);
  }

  /**
  * @return the total amount that got deposited for _account over the whole lifecycle with all decimal places
  */
  function getTotalDeposit(address _account) external view returns(uint256) {
    return totalDeposit[_account];
  }

  /** 
  * @return the amount of tokens still in vesting for _account
  */
  function getTotalVestingBalance(address _account) external view returns(uint256) {
    return totalDeposit[_account] - drainedAmount[_account];
  }

  /**
  * @return the percentage that is retrievable, 100 = 100%
  */
  function getRetrievablePercentage() external view returns(uint256) {
    return _getPercentage() / 100;
  }

  /**
  * @notice useful for easy snapshot implementation
  * @return the balance of token for this account plus the amount that is still vested for account
  */
  function balanceOf(address account) external view returns(uint256) {
    return token.balanceOf(account) + totalDeposit[account] - drainedAmount[account];
  }

  /**
  * @return the amount that _account can retrieve at that block with all decimals
  */
  function getRetrievableAmount(address _account) public view returns(uint256) {
    if(_getPercentage() * totalDeposit[_account] / 1e4 > drainedAmount[_account]) {
      return (_getPercentage() * totalDeposit[_account] / 1e4) - drainedAmount[_account];
    }else {
      return 0;
    }
  }

  function _rawDeposit(address _from, address _for, uint256 _amount) private {
    require(token.transferFrom(_from, address(this), _amount));
    totalDeposit[_for] += _amount;
    emit TokensDeposited(_for, _amount);
  }

  function _rawRetrieve(address account, uint256 amount) private {
    drainedAmount[account] += amount;
    token.transfer(account, amount);
    assert(drainedAmount[account] <= totalDeposit[account]);
    emit TokensRetrieved(account, amount);
  }

  /**
  * @dev the core calculation method
  * @dev returns 1e4 for 100%; 1e3 for 10%; 1e2 for 1%; 1e1 for 0.1% and 1e0 for 0.01%
  */
  function _getPercentage() private view returns(uint256) {
    if (cliff == 0) {
      return _getPercentageNoCliff();
    }else {
      return _getPercentageWithCliff();
    }
  }

  function _getPercentageNoCliff() private view returns(uint256) {
    if (startTime > block.timestamp) {
      return 0;
    }else if (startTime + duration > block.timestamp) {
      return (1e4 * (block.timestamp - startTime)**exp) / duration**exp;
    }else {
      return 1e4;
    }
  }

  function _getPercentageWithCliff() private view returns(uint256) {
    if (block.timestamp + cliffDelay < startTime) {
      return 0;
    }else if (block.timestamp < startTime) {
      return cliff;
    }else if (1e4 * (block.timestamp - startTime)**exp / duration**exp + cliff < 1e4) {
      return (1e4 * (block.timestamp - startTime)**exp / duration**exp) + cliff;
    }else {
      return 1e4;
    }
  }
}