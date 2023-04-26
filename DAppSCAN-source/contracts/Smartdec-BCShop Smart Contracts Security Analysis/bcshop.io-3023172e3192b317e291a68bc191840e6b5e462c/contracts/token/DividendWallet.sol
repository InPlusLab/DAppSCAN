pragma solidity ^0.4.10;

import './ValueTokenAgent.sol';
import './ValueToken.sol';
import './IDividendWallet.sol';
import '../common/SafeMath.sol';
import '../common/ReentryProtected.sol';

/* Based on 
https://medium.com/@weka/dividend-bearing-tokens-on-ethereum-42d01c710657
*/

/**@dev Can distribute all stored ether among token holders */
contract DividendWallet is ValueTokenAgent, IDividendWallet, SafeMath, ReentryProtected {

    event Withdraw(address receiver, uint256 amount);    
    
    /**@dev Ether balance to withdraw */
    mapping (address => uint256) public etherBalance;

    /**@dev The contract balance at last claim (transfer or withdraw) */
    uint lastBalance;
    
    /**@dev Sets token to watch transfer operations */
    function DividendWallet(ValueToken token) ValueTokenAgent(token) {    
    }

    function () payable {}

    /**@dev ValueTokenAgnet override. Validates the state of each holder's dividend to be paid */
    function tokenIsBeingTransferred(address from, address to, uint256 amount) valueTokenOnly {
        require(from != to);        
        
        updateHolder(from);
        updateHolder(to);
    }

    /**@dev ValueTokenAgent override */
    function tokenChanged(address holder, uint256 amount) valueTokenOnly {
        updateHolder(holder);
    }

    /**@dev Withdraws all sender's ether balance */
    function withdrawAll() returns (bool) {
        require(!valueToken.reserved(msg.sender));
        return doWithdraw(msg.sender, etherBalanceOf(msg.sender));
    }
    
    /**@dev Account specific ethereum balance getter */
    function etherBalanceOf(address holder) constant returns (uint balance) {
        balance = safeAdd(etherBalance[holder], claimableEther(holder));
    }    

    /** @dev Updates holder state before transfer tokens or ether withdrawal */
    function updateHolder(address holder) internal;

    /**@dev Returns amount of ether that specified holder can withdraw  */
    function claimableEther(address holder) internal constant returns (uint256 eth) {holder; eth;}

    /**@dev Account withdrawl function */
    //function doWithdraw(address holder, uint amount) internal returns (bool);
    function doWithdraw(address holder, uint amount) 
        internal 
        // preventReentry
        returns (bool success)
    {
        updateHolder(holder);
        
        // check balance and withdraw on valid amount
        require(amount <= etherBalance[holder]);
        etherBalance[holder] = safeSub(etherBalance[holder], amount);

        lastBalance = safeSub(lastBalance, amount);
        
        Withdraw(holder, amount);        
        holder.transfer(amount);    

        success = true;
    }
}

