// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

//Flexible Vesting Schedule with easy Snapshot compatibility designed by Phil Thomsen @theDAC
//for more information please visit: github.com


interface Ivesting {

  /**
   * @notice initializes the contract, with all parameters set at once
   * @dev   can only be called once
   * @param _token the only token contract that is accepted in this vesting instance
   * @param _owner account that can call decreaseVesting(); set address(0) to have no owner
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
    external;

  /**
  * @notice same as depositFor but with memory array as input
  */
  function depositForCrowd(address[] memory _recipient, uint256[] memory _amount) external;

  /**
  * @notice deposits the amount owned by _recipient from sender for _recipient into this contract
  * @param _recipient the address the funds are vested for
  * @dev only useful in specific contexts like having to burn a wallet and deposit it back in the vesting contract e.g.
  */
  function depositAllFor(address _recipient) external;

  /**
  * @notice user method to retrieve all that is retrievable
  * @notice reverts when there is nothing to retrieve to save gas
  */
  function retrieve() external;

  /**
  * @notice retrieve for an array of addresses at once, useful if users are unable to use the retrieve method or to save gas with mass retrieves
  * @dev does NOT revert when one of the accounts has nothing to retrieve
  */
  function retrieveFor(address[] memory accounts) external;

  /**
  * @notice if the ownership got renounced (owner == 0), then this function is uncallable and the vesting is trustless for benificiary
  * @dev only callable by the owner of this instance
  * @dev amount will be stuck in the contract and effectively burned
  */
  function decreaseVesting(address _account, uint256 amount) external;

  /**
  * @return the total amount that got deposited for _account over the whole lifecycle with all decimal places
  */
  function getTotalDeposit(address _account) external view returns(uint256);

  /**
  * @return the percentage that is retrievable, 100 = 100%
  */
  function getRetrievablePercentage() external view returns(uint256);

  /**
  * @notice useful for easy snapshot implementation
  * @return the balance of token for this account plus the amount that is still vested for account
  */
  function balanceOf(address account) external view returns(uint256);

  /**
  * @return the amount that _account can retrieve at that block with all decimals
  */
  function getRetrievableAmount(address _account) external view returns(uint256);

  /** 
  * @return the amount of tokens still in vesting for _account
  */
  function getTotalVestingBalance(address _account) external view returns(uint256);

  /**
  * @notice sender can deposit tokens for someone else
  * @param _recipient the use to deposit for 
  * @param _amount the amount of tokens to deposit with all decimals
  */
  function depositFor(address _recipient, uint256 _amount) external;

}