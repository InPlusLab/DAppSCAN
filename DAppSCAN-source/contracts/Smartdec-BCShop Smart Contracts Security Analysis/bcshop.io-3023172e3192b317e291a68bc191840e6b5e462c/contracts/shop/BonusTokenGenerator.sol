pragma solidity ^0.4.10;

import "../token/ValueTokenAgent.sol";
import "../token/ReturnTokenAgent.sol";
import "../token/TokenHolder.sol";
import "../token/FloatingSupplyToken.sol";
import "../common/SafeMath.sol";
import "../common/Active.sol";
import "./IFund.sol";
import "./ITokenGenerator.sol";

/**@dev A fund that issues bonus tokens in exchange for BCSTokens */
contract BonusTokenGenerator is ValueTokenAgent, ReturnTokenAgent, TokenHolder, Active, SafeMath, ITokenGenerator {
    
    event AllowedSpenderSet(address indexed spender, bool state);
    event EtherRequested(address indexed spender, uint256 amount);

    uint256 constant MULTIPLIER = 10 ** 18;    

    /**@dev Exchange rate BonusToken/Ether */
    uint256 public tokenEtherRate;

    /**@dev Bonus token */
    FloatingSupplyToken public bonusToken;

    /**@dev Bonus token price expressed in real(value) tokens */
    uint256 public bonusTokenPrice; 

    /**@dev Fund that contains accumulated fee for bonus tokens */
    IFund public etherFund;

    /**@dev List of addresses that are allowed to request ether from the fund on behalf of this contract */
    mapping (address=>bool) public allowedEtherSpenders;

    /**@dev The running tally of dividends points accured by dividend/totalSupply at each dividend payment */
    uint tokenPoints;

    /**@dev tokenPoints at the moment of holder's last update*/
    mapping (address => uint256) lastClaimedPoints;

    /**@dev bonus token points accumulated so far for all holders */
    mapping (address => uint256) bonusTokenPoints;

    /**@dev The fund ether balance part at last claim (transfer or withdraw) */
    uint256 lastBalance;    
        
    function BonusTokenGenerator(
        ValueToken _realToken, 
        FloatingSupplyToken _bonusToken,              
        uint256 _tokenEtherRate,
        uint256 _bonusTokenPrice)
        public
        ValueTokenAgent(_realToken)
    {
        require(_tokenEtherRate > 0 && _bonusTokenPrice > 0);

        bonusToken = _bonusToken;
        bonusTokenPrice = _realToken.getRealTokenAmount(_bonusTokenPrice);
        tokenEtherRate = _tokenEtherRate;
    }

    /**@dev Changes core generator settings */
    function setParams(
        FloatingSupplyToken _bonusToken,          
        uint256 _bonusTokenPrice, 
        uint256 _tokenEtherRate
    ) 
        public
        ownerOnly
    {
        require(_tokenEtherRate > 0 && _bonusTokenPrice > 0);
        
        tokenEtherRate = _tokenEtherRate;
        bonusToken = _bonusToken;
        bonusTokenPrice = valueToken.getRealTokenAmount(_bonusTokenPrice);        
    }

    /**@dev Changes ether fund */
    function setFund(IFund newFund) public ownerOnly {
        etherFund = newFund;
    }
    
    /**@dev Changes state of ether spender address  */
    function setEtherSpender(address spender, bool state) public ownerOnly {
        allowedEtherSpenders[spender] = state;
        AllowedSpenderSet(spender, state);
    }

    /**@dev allows another contracts to request ether from this */
    function requestEther(uint amount) public {
        require(allowedEtherSpenders[msg.sender]);

        uint256 fundBalance = fundEtherBalance();

        // Update unprocessed deposits
        if (lastBalance != fundBalance) {
            tokenPoints = totalTokenPoints();
            lastBalance = fundBalance;
        }   
        lastBalance = safeSub(lastBalance, amount);

        etherFund.withdrawTo(msg.sender, amount);        

        EtherRequested(msg.sender, amount);
    }

    /**@dev ReturnTokenAgent override */
    function returnToken(address from, uint256 amountReturned) 
        public 
        activeOnly 
        returnableTokenOnly 
    {
        //bcs token is exchanged for bcb tokens
        if (msg.sender == address(valueToken)) {
            require(amountReturned >= bonusTokenPrice);
            issueBonusTokens(from); //issue bonus tokens

            //return the remainder
            if (amountReturned > bonusTokenPrice) {
                valueToken.transfer(from, amountReturned - bonusTokenPrice); 
            }
        }     
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
   
    /**@dev how many tokens can be issued to specific account */
    function bonusTokensToIssue(address holder) public constant returns (uint256) {
        return safeAdd(bonusTokenPoints[holder], tokensSinceLastUpdate(holder));
    } 

    //
    // Internals
    //

    /**@dev Returns amount of fund ether that goes to token generation */
    function fundEtherBalance() internal constant returns (uint256) {
        return etherFund.etherBalanceOf(this);
    }

    /**@dev Returns amount of tokens generated for specific account since last update*/
    function tokensSinceLastUpdate(address holder) internal constant returns (uint256) {
        return tokenEtherRate * 
            (totalTokenPoints() - lastClaimedPoints[holder]) * valueToken.balanceOf(holder) / 
            MULTIPLIER; 
    }

    /**@dev returns total dividend token points up to date */
    function totalTokenPoints() internal constant returns (uint256) {        
        return safeAdd(tokenPoints, MULTIPLIER * safeSub(fundEtherBalance(), lastBalance) / valueToken.getValuableTokenAmount());    
    }

    /**@dev updates ValueToken holder state */
    function updateHolder(address holder) internal {
        //uint256 fundBalance = fundEtherBalance();

        // Update unprocessed deposits
        if (lastBalance != fundEtherBalance()) {
            tokenPoints = totalTokenPoints();
            lastBalance = fundEtherBalance();
        }   

        //don't update balance for reserved tokens
        if (!valueToken.reserved(holder)) {
            // Claim share of deposits since last claim
            bonusTokenPoints[holder] = bonusTokensToIssue(holder);

            // Save dividend points for holder
            if(lastClaimedPoints[holder] != tokenPoints) {
                lastClaimedPoints[holder] = tokenPoints;
            }
        }            
    }
    
    /**@dev issues an amount of bonus tokens that belongs to specific holder */
    function issueBonusTokens(address holder) internal {
        updateHolder(holder);
    
        uint256 amount = bonusTokensToIssue(holder);
        require(amount > 0);
        bonusTokenPoints[holder] = safeSub(bonusTokenPoints[holder], amount);        
        
        bonusToken.mint(holder, amount);   
    } 
}