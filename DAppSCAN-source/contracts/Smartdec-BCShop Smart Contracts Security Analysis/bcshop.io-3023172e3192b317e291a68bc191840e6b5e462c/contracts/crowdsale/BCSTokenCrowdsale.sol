pragma solidity ^0.4.10;

import './BCSCrowdsale.sol';

///Crowdsale that accepts tokens as a payment in addition to common ether payments
///Crowdsale token holder should ERC20.transfer reserved amount of tokens to crowdsale contract 
contract BCSTokenCrowdsale is BCSCrowdsale {
    
    function BCSTokenCrowdsale(
        ITokenPool _tokenPool,
        IInvestRestrictions _restrictions,        
        address _beneficiary, 
        uint256 _startTime, 
        uint256 _durationInHours, 
        uint256 _goalInWei,
        uint256 _tokensForOneEther,
        uint256 _bonusPct        
    ) BCSCrowdsale(
        _tokenPool,
        _restrictions,
        _beneficiary, 
        _startTime, 
        _durationInHours, 
        _goalInWei, 
        _tokensForOneEther, 
        _bonusPct) {
    }

    /**@dev ReturnTokenAgent override. Transfers some crowdsale tokens when bonus tokens are received */
    function returnToken(address from, uint256 amountReturned) returnableTokenOnly {
        super.returnToken(from, amountReturned);

        if(msg.sender != address(tokenPool.token())) {
            require(getState() == State.Active);
            
            //adjust amount according to decimals
            //msg.sender is returnable tokens itself
            ReturnableToken rToken = ReturnableToken(msg.sender);

            //accept returnable tokens 1:1
            tokenPool.token().transfer(from, amountReturned * (uint256(10) ** tokenPool.token().decimals()) / (uint256(10) ** rToken.decimals())); 
        }
    }

    /**@dev Returns unclaimed tokens after the end of crowdsale back to owner */
    function returnUnclaimedTokens() managerOnly {
        require(getState() == State.FinishedSuccess);

        tokenPool.token().transfer(msg.sender, tokenPool.token().balanceOf(this));
    }
}