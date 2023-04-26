pragma solidity ^0.4.10;

//import "./IBonusTokenFund.sol";
import "../token/ValueTokenAgent.sol";
import "../token/ReturnTokenAgent.sol";
import "../token/TokenHolder.sol";
import "../token/FloatingSupplyToken.sol";
import "../common/SafeMath.sol";

/**@dev A fund that issues bonus tokens in exchange for BCSTokens */
contract BonusTokenFund is ValueTokenAgent, ReturnTokenAgent, TokenHolder, SafeMath {
    
    uint constant MULTIPLIER = 10 ** 18;    

    /**@dev The running tally of dividends points accured by dividend/totalSupply at each dividend payment */
    uint tokenPoints;

    /**@dev tokenPoints at the moment of holder's last update*/
    mapping (address => uint256) lastClaimedPoints;

    /**@dev bonus token points accumulated so far for all holders */
    mapping (address => uint256) bonusTokenPoints;

    /**@dev true if address is allowed to exchange tokens for ether compensation */
    //mapping (address => bool) public allowedEtherReceiver;

    /**@dev the share of fee that is spent for bonus token issuance, (1/1000) */
    uint16 public tokenFeePromille;

    /**@dev exchange rate BonusToken/Ether */
    uint16 public tokenEtherRate;

    /**@dev The contract balance at last claim (transfer or withdraw) */
    uint lastBalance;

    /**@dev Bonus token */
    FloatingSupplyToken public bonusToken;

    /**@dev Bonus token price expressed in real(value) tokens */
    uint256 public bonusTokenPrice; 

    /**@dev all ether deposited to fund */
    uint256 public maxBalance;

    /**@dev ether on the moment of last provider withdrawal */
    uint256 public lastWithdrawBalance;

    function BonusTokenFund(
        ValueToken _realToken, 
        FloatingSupplyToken _bonusToken, 
        uint16 _tokenEtherRate, 
        uint256 _bonusTokenPrice,
        uint16 _tokenFeePromille) 
        public
        ValueTokenAgent(_realToken)
    {
        bonusToken = _bonusToken;
        tokenEtherRate = _tokenEtherRate;
        tokenFeePromille = _tokenFeePromille;
        bonusTokenPrice = _realToken.getRealTokenAmount(_bonusTokenPrice);        
    }

    function() payable public {}

    /**@dev IBonusTokenFund override. Allows to send ether to specified address in exchange for bonusToken */
    // function allowCompensationFor(address to) public managerOnly {
    //     allowedEtherReceiver[to] = true;
    // }

    /**@dev how many tokens can be issued to specific account */
    function bonusTokensToIssue(address holder) public constant returns (uint256) {
        return safeAdd(bonusTokenPoints[holder], tokensSinceLastUpdate(holder));
    } 

    /**@dev Sets new bonustoken/ether exchange rate */
    function setExchangeRate(uint16 newTokenEtherRate) public managerOnly {
        tokenEtherRate = newTokenEtherRate;
    }    

    /**@dev ReturnTokenAgent override */
    function returnToken(address from, uint256 amountReturned) public returnableTokenOnly {
        //bcs token is exchanged for bcb tokens
        if (msg.sender == address(valueToken)) {
            require(amountReturned >= bonusTokenPrice);
            issueBonusTokens(from); //issue bonus tokens

            //return the remainder
            if (amountReturned > bonusTokenPrice) {
                valueToken.transfer(from, amountReturned - bonusTokenPrice); 
            }
        }
        //bcb tokens are exchanged for ether compensation
        // } else if (msg.sender == address(bonusToken)) { 
        //     require(allowedEtherReceiver[from]);                       
        //     returnEther(from, amountReturned); //return ether            
        //     bonusToken.burn(amountReturned); //burn bonus tokens
        // }
    }

    /**@dev ValueTokenAgent override */
    function tokenIsBeingTransferred(address from, address to, uint256 amount) public valueTokenOnly {
        require(from != to);        
        
        updateHolder(from);
        updateHolder(to);
    }

    /**@dev ValueTokenAgent override */
    function tokenChanged(address holder, uint256 amount) public valueTokenOnly {
        updateHolder(holder);
    }

   

    //
    // Internals
    //

    /**@dev Returns amount of tokens generated for specific account since last update*/
    function tokensSinceLastUpdate(address holder) internal constant returns (uint256) {
        return tokenEtherRate * 
            tokenFeePromille * 
            (totalTokenPoints() - lastClaimedPoints[holder]) * valueToken.balanceOf(holder) / 
            (MULTIPLIER * 1000); 
    }    

    /**@dev returns total dividend token points up to date */
    function totalTokenPoints() internal constant returns (uint256) {
        return safeAdd(tokenPoints, MULTIPLIER * safeSub(this.balance, lastBalance) / valueToken.getValuableTokenAmount());    
    }

    /**@dev updates ValueToken holder state */
    function updateHolder(address holder) internal {  
        // Update unprocessed deposits
        if (lastBalance != this.balance) {
            tokenPoints = totalTokenPoints();
            lastBalance = this.balance;
        }   

        //don't update balance for reserved tokens
        if (!valueToken.reserved(holder)) {
            // Claim share of deposits since last claim
            bonusTokenPoints[holder] = bonusTokensToIssue(holder);
        }
        
        // Save dividend points for holder
        if(lastClaimedPoints[holder] != tokenPoints) {
            lastClaimedPoints[holder] = tokenPoints;
        }
    }
    
    /**@dev issues an amount of bonus tokens that belongs to specific holder */
    function issueBonusTokens(address holder) internal {
        updateHolder(holder);
    
        uint256 amount = bonusTokensToIssue(holder);        
        bonusTokenPoints[holder] = safeSub(bonusTokenPoints[holder], amount);        
        
        bonusToken.mint(holder, amount);   
    }

    /**@dev transfers ether in exchange for bonus tokens */
    function returnEther(address to, uint256 bonusTokensAmount) internal {        
        uint256 etherAmount = bonusTokensAmount / tokenEtherRate;        
        lastBalance = safeSub(lastBalance, etherAmount);
        to.transfer(etherAmount);
    }
}