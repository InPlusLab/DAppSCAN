pragma solidity ^0.4.10;

import './BCSCrowdsale.sol';

/**@dev Crowdsale that keeps a part of raised funds for a partner */
contract BCSPartnerCrowdsale is BCSCrowdsale {
    
    /**@dev Part of funds that is granted to partner */
    uint16 public partnerPromille;
    
    /**@dev Partner that can receive a part of collected funds */
    address public partner;

    /**@dev True if partner already withdrew */
    bool public partnerWithdrew;    

    function BCSPartnerCrowdsale(        
        ITokenPool _tokenPool,
        IInvestRestrictions _restrictions,
        address _beneficiary, 
        uint256 _startTime, 
        uint256 _durationInHours, 
        uint256 _goalInWei,
        uint256 _tokensForOneEther,
        uint256 _bonusPct,        
        address _partner,
        uint16 _partnerPromille        
    ) BCSCrowdsale(
        _tokenPool, 
        _restrictions,
        _beneficiary, 
        _startTime, 
        _durationInHours, 
        _goalInWei, 
        _tokensForOneEther, 
        _bonusPct) {

        partner = _partner;
        partnerPromille = _partnerPromille;   
        partnerWithdrew = false;     
    }

     /**@dev BCSCrowdsale override */
    function amountToBeneficiary() constant returns (uint256) {
        return weiCollected - amountToPartner();
    }

    /**@dev Amount of funds granted to partner */
    function amountToPartner() constant returns (uint256) {
        if (partner != 0x0 && partnerPromille != 0) {
            return weiCollected * partnerPromille / 1000;
        } else {
            return 0;
        }
    }

    /**@dev Transfers all collected funds to beneficiary*/
    function transferToPartner() {
        require(getState() == State.FinishedSuccess && !partnerWithdrew);

        partnerWithdrew = true;
        uint256 amount = amountToPartner();
        partner.transfer(amount);
        
        Refund(partner, amount);        
    }
}