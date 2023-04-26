pragma solidity ^0.4.10;

import './DividendWallet.sol';

/* Based on 
https://medium.com/@weka/dividend-bearing-tokens-on-ethereum-42d01c710657
*/


/**@dev Can distribute all stored ether among fixed supply token holders. 
It's better not to use it at all*/
contract DividendWalletFixed is DividendWallet {

    /**@dev The totalDeposits at the time of last claim */
    mapping (address => uint256) public lastSumDeposits;
        
    /**@dev The summation of ether deposited up to when a holder last triggered a claim */
    uint sumDeposits;    

    /**@dev Sets token to watch transfer operations */
    function DividendWalletFixed(ValueToken token) DividendWallet(token) {        
    }

    /**@dev Returns total ether deposits to date */
    function deposits() constant returns (uint) {
        return safeAdd(sumDeposits, safeSub(this.balance, lastBalance));
    }
    
    /**@dev DividendWallet override */
    function claimableEther(address holder) internal constant returns (uint256 eth) {
        // shortly that means [tokens * (deposits() - lastSumDeposits) / totalTokens]
        eth = safeDiv(
                safeMult(
                    valueToken.balanceOf(holder), 
                    safeSub(deposits(), lastSumDeposits[holder])), 
                valueToken.getValuableTokenAmount());
    }

    /**@dev DividendWallet override */
    function updateHolder(address holder) internal {
        // Update unprocessed deposits
        if (lastBalance != this.balance) {
            sumDeposits = deposits();
            lastBalance = this.balance;
        }

        //don't update balance for reserved tokens
        if (!valueToken.reserved(holder)) {
            // Claim share of deposits since last claim
            etherBalance[holder] = safeAdd(etherBalance[holder], claimableEther(holder));
            
            // Snapshot deposits summation
            lastSumDeposits[holder] = sumDeposits;
        }
    }
}

