pragma solidity ^0.4.18;

import "../common/Owned.sol";
import "../token/IERC20Token.sol";

/**@dev This contract holds tokens and unlock at specific dates.
unlockDates - array of UNIX timestamps when unlock happens
unlockAmounts - total amount of tokens that are unlocked on that date, the last element should equal to 0
For example, if 
1st tranche unlocks 10 tokens, 
2nd unlocks 15 tokens more
3rd unlocks 30 tokens more
4th unlocks 40 tokens more - all the rest 
then unlockAmounts should be [10, 25, 55, 95]
 */
contract CustomTrancheWallet is Owned {

    IERC20Token public token;
    address public beneficiary;
    uint256 public initialFunds; //initial funds at the moment of lock 
    bool public locked; //true if funds are locked
    uint256[] public unlockDates;
    uint256[] public unlockAmounts;
    uint256 public alreadyWithdrawn; //amount of tokens already withdrawn

    function CustomTrancheWallet(
        IERC20Token _token, 
        address _beneficiary, 
        uint256[] _unlockDates, 
        uint256[] _unlockAmounts
    ) 
    public 
    {
        token = _token;
        beneficiary = _beneficiary;
        unlockDates = _unlockDates;
        unlockAmounts = _unlockAmounts;

        require(paramsValid());
    }

    /**@dev Returns total number of scheduled unlocks */
    function unlocksCount() public constant returns(uint256) {
        return unlockDates.length;
    }

    /**@dev Returns amount of tokens available for withdraw */
    function getAvailableAmount() public constant returns(uint256) {
        if (!locked) {
            return token.balanceOf(this);
        } else {
            return amountToWithdrawOnDate(now) - alreadyWithdrawn;
        }
    }    

    /**@dev Returns how many token can be withdrawn on specific date */
    function amountToWithdrawOnDate(uint256 currentDate) public constant returns (uint256) {
        for (uint256 i = unlockDates.length; i != 0; --i) {
            if (currentDate > unlockDates[i - 1]) {
                return unlockAmounts[i - 1];
            }
        }
        return 0;
    }

    /**@dev Returns true if params are valid */
    function paramsValid() public constant returns (bool) {        
        if (unlockDates.length == 0 || unlockDates.length != unlockAmounts.length) {
            return false;
        }        

        for (uint256 i = 0; i < unlockAmounts.length - 1; ++i) {
            if (unlockAmounts[i] >= unlockAmounts[i + 1]) {
                return false;
            }
            if (unlockDates[i] >= unlockDates[i + 1]) {
                return false;
            }
        }
        return true;
    }

    /**@dev Sends available amount to stored beneficiary */
    function sendToBeneficiary() public {
        uint256 amount = getAvailableAmount();
        alreadyWithdrawn += amount;
        require(token.transfer(beneficiary, amount));
    }

    /**@dev Locks tokens according to stored schedule */
    function lock() public ownerOnly {
        require(!locked);
        require(token.balanceOf(this) == unlockAmounts[unlockAmounts.length - 1]);

        locked = true;
    }

    /**@dev Changes unlock schedule, can be called only by the owner and if funds are not locked*/
    function setParams(        
        uint256[] _unlockDates, 
        uint256[] _unlockAmounts
    ) 
    public 
    ownerOnly 
    {
        require(!locked);        

        unlockDates = _unlockDates;
        unlockAmounts = _unlockAmounts;

        require(paramsValid());
    }    

    /**@dev Sets new beneficiary, can be called only by the owner */
    function setBeneficiary(address _beneficiary) public ownerOnly {
        beneficiary = _beneficiary;
    }
}