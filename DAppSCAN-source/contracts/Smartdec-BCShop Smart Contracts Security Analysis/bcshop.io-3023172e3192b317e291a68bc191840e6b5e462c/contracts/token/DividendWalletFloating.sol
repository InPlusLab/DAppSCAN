pragma solidity ^0.4.10;

import './DividendWallet.sol';

/* Based on 
https://medium.com/@weka/dividend-bearing-tokens-on-ethereum-42d01c710657
*/

/**@dev Can distribute all stored ether among floating supply token holders. */
contract DividendWalletFloating is DividendWallet {

    uint constant MULTIPLIER = 10 ** 18;

    /**@dev The running tally of dividends points accured by dividend/totalSupply at each dividend payment */
    uint dividendPoints;    

    /**@dev dividendPoints at the moment of holder's last update*/
    mapping (address => uint256) lastClaimed;

    function DividendWalletFloating(ValueToken token) DividendWallet(token) {}
    
    function totalDividendPoints() constant returns (uint256) {
        return safeAdd(dividendPoints, MULTIPLIER * safeSub(this.balance, lastBalance) / valueToken.getValuableTokenAmount());
        //return safeAdd(dividendPoints, MULTIPLIER * (this.balance - lastBalance) / valueToken.getValuableTokenAmount()); 
    }    

    /**@dev DividendWallet override */
    function updateHolder(address holder) internal {  
        // Update unprocessed deposits
        if (lastBalance != this.balance) {
            dividendPoints = totalDividendPoints();
            lastBalance = this.balance;
        }   

        //don't update balance for reserved tokens
        if (!valueToken.reserved(holder)) {
            // Claim share of deposits since last claim
            etherBalance[holder] = safeAdd(etherBalance[holder], claimableEther(holder));
        }
        // Save dividend points for holder
        lastClaimed[holder] = dividendPoints;
    }    

    /**@dev DividendWallet override */
    function claimableEther(address holder) internal constant returns (uint256 eth) {
        eth = (totalDividendPoints() - lastClaimed[holder]) * valueToken.balanceOf(holder) / MULTIPLIER; 
    }    
}