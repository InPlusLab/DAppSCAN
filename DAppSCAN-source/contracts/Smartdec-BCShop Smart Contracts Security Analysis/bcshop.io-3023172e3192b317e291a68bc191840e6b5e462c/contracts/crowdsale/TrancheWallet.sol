pragma solidity ^0.4.10;

import "../common/Owned.sol";

/**@dev Distributes some amount of currency in small portions available to withdraw once in a period */
contract TrancheWallet is Owned {
    address public beneficiary;         //funds are to withdraw to this account
    uint256 public tranchePeriodInDays; //one tranche 'cooldown' time
    uint256 public trancheAmountPct;    //one tranche amount 
        
    uint256 public lockStart;           //when funds were locked
    uint256 public completeUnlockTime;  //when funds are unlocked completely
    uint256 public initialFunds;        //funds to divide into tranches
    uint256 public tranchesSent;        //tranches already sent to beneficiary

    event Withdraw(uint256 amount, uint256 tranches);

    function TrancheWallet(
        address _beneficiary, 
        uint256 _tranchePeriodInDays,
        uint256 _trancheAmountPct        
        ) 
    {
        beneficiary = _beneficiary;
        tranchePeriodInDays = _tranchePeriodInDays;
        trancheAmountPct = _trancheAmountPct;
        tranchesSent = 0;
        completeUnlockTime = 0;
    }

    /**@dev Sets new beneficiary to receive funds */
    function setBeneficiary(address newBeneficiary) public ownerOnly {
        beneficiary = newBeneficiary;
    }

    //Locks all funds on account so that it's possible to withdraw only specific tranche amount.
    //Funds will be unlocked completely in a given amount of days 
    //Can be made only one time
    function lock(uint256 lockPeriodInDays) public ownerOnly {
        require(lockStart == 0);

        initialFunds = currentBalance();//this.balance;
        lockStart = now;
        completeUnlockTime = lockPeriodInDays * 1 days + lockStart;
    }

    /**@dev Sends available tranches to beneficiary account*/
    function sendToBeneficiary() {
        uint256 amountToWithdraw;
        uint256 tranchesToSend;
        (amountToWithdraw, tranchesToSend) = amountAvailableToWithdraw();

        require(amountToWithdraw > 0);

        tranchesSent += tranchesToSend;
        doTransfer(amountToWithdraw);

        Withdraw(amountToWithdraw, tranchesSent);
    }

    /**@dev Calculates available amount to withdraw */
    function amountAvailableToWithdraw() constant returns (uint256 amount, uint256 tranches) {        
        if (currentBalance() > 0) {
            if(now > completeUnlockTime) {
                //withdraw everything
                amount = currentBalance();
                tranches = 0;
            } else {
                //withdraw tranche                
                uint256 periodsSinceLock = (now - lockStart) / (tranchePeriodInDays * 1 days);
                tranches = periodsSinceLock - tranchesSent + 1;                
                amount = tranches * oneTrancheAmount();

                //check if exceeding current limit
                if(amount > currentBalance()) {
                    amount = currentBalance();
                    tranches = amount / oneTrancheAmount();
                }
            }
        } else {
            amount = 0;
            tranches = 0;
        }
    }

    /**@dev Returns the size of one tranche */
    function oneTrancheAmount() constant returns(uint256) {
        return trancheAmountPct * initialFunds / 100; 
    }

    /**@dev Returns current balance to be distributed to portions*/
    function currentBalance() internal constant returns(uint256);

    /**@dev Transfers given amount of currency to the beneficiary */
    function doTransfer(uint256 amount) internal;
}
