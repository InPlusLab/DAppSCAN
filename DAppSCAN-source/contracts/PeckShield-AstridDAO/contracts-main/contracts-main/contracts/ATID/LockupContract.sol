// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../Dependencies/SafeMath.sol";
import "../Interfaces/IATIDToken.sol";

/*
* The lockup contract architecture utilizes a single LockupContract, with an unlockTime. The unlockTime is passed as an argument 
* to the LockupContract's constructor. The contract's balance can be withdrawn by the beneficiary when block.timestamp > unlockTime,
* following a release schedule.

* Within the lockup time period, the deployer of the ATIDToken may transfer ATID only to valid 
* LockupContracts, and no other addresses (this is enforced in ATIDToken.sol's transfer() function).
* 
* The above two restrictions ensure that until lockup time has passed, ATID tokens originating from LockupContract cannot 
* enter circulating supply and cannot be staked to earn system revenue.
*/
contract LockupContract {
    using SafeMath for uint;

    // --- Data ---
    string constant public NAME = "LockupContract";

    // uint constant public SECONDS_IN_ONE_YEAR = 31536000; 
    uint constant public SECONDS_IN_ONE_MONTH = 2628000; 
    // uint constant public SECONDS_IN_SIX_MONTHS = SECONDS_IN_A_MONTH * 6; 

    address public immutable beneficiary;

    IATIDToken public atidToken;
    // Initial amount locked by this contract.
    uint public immutable initialAmount;
    // Amount that has been claimed.
    uint public claimedAmount;

    // Timestamp of when the contract is deployed (and when unlock months start to be counted).
    uint public immutable deploymentStartTime;
    // Months before initial unlocking can happen.
    uint public immutable monthsToWaitBeforeUnlock;
    // Release schedule: how many months after unlocking should the tokens be gradually distributed.
    uint public immutable releaseSchedule;

    // --- Events ---

    event LockupContractCreated(address _beneficiary, uint _amount, uint _monthsToWaitBeforeUnlock, uint _releaseSchedule);
    event LockupContractWithdrawn(uint _ATIDwithdrawal);

    // --- Functions ---

    constructor 
    (
        address _atidTokenAddress, 
        address _beneficiary, 
        uint _amount,
        uint _monthsToWaitBeforeUnlock,
        uint _releaseSchedule
    )
    {
        require(_releaseSchedule > 0, "LockupContract: release schedule cannot be 0");

        atidToken = IATIDToken(_atidTokenAddress);
        
        beneficiary =  _beneficiary;
        deploymentStartTime = block.timestamp;
        monthsToWaitBeforeUnlock = _monthsToWaitBeforeUnlock;
        releaseSchedule = _releaseSchedule;

        initialAmount = _amount;
        claimedAmount = 0;

        emit LockupContractCreated(_beneficiary, _amount, _monthsToWaitBeforeUnlock, _releaseSchedule);
    }

    function _getReleasedAmount() internal view returns (uint) {
        uint unlockTimestamp = deploymentStartTime + (monthsToWaitBeforeUnlock * SECONDS_IN_ONE_MONTH);
        if (block.timestamp < unlockTimestamp) {
            return 0;
        }
        uint monthsSinceUnlock = ((block.timestamp - unlockTimestamp) / SECONDS_IN_ONE_MONTH) + 1;
        uint monthlyReleaseAmount = initialAmount / releaseSchedule;
        uint releasedAmount = monthlyReleaseAmount * monthsSinceUnlock;
        
        if (releasedAmount > initialAmount){
            return initialAmount;
        }

        return releasedAmount;
    }

    // Whether the beneficiary can widthdraw a certain amount of ATID at this moment.
    function canWithdraw(uint amount) public view returns (bool) {
        uint claimableAmount = _getReleasedAmount() - claimedAmount; 
        return amount <= claimableAmount; 
    }

    // Withdraw a certain amount of ATID from this contract to the beneficiary.
    function withdrawATID(uint amount) external {
        require(amount > 0, "LockupContract: requested amount should > 0");
        require(canWithdraw(amount), "LockupContract: requested amount cannot be withdrawed");

        IATIDToken atidTokenCached = atidToken;
        // Also subject to initial locked time.
        require(atidTokenCached.transfer(beneficiary, amount), "LockupContract: cannot withdraw ATID");
        claimedAmount += amount;

        emit LockupContractWithdrawn(amount);
    }
}
