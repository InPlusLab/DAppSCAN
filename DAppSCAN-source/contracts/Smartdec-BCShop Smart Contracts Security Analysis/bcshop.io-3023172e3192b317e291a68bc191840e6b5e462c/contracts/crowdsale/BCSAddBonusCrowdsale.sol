pragma solidity ^0.4.18;

import "./BCSCrowdsale.sol";

/**@dev Addition to token-accepting crowdsale contract. 
    Allows to set bonus decreasing with time. 
    For example, if we ant to set bonus taht decreases from +20% to +5% each week -3%,
    and then stays on +%5, then constructor parameters should be:
    _bonusPct = 20
    _maxDecreasePct = 15
    _decreaseStepPct = 3
    _stepDurationDays = 7

    In addition, it allows to set investment steps with different bonus. 
    For example, if there is following scheme:
    Default bonus +20%
    1-5 ETH : +1% bonus, 
    5-10 ETH : +2% bonus,
    10-20 ETH : +3% bonus,
    20+ ETH : +5% bonus, 
    then constructor parameters should be:
    _bonusPct = 20
    _investSteps = [1,5,10,20]
    _bonusPctSteps = [1,2,3,5]
    */ 
contract BCSAddBonusCrowdsale is BCSCrowdsale {
    
    uint256 public decreaseStepPct;
    uint256 public stepDuration;
    uint256 public maxDecreasePct;
    uint256[] public investSteps;
    uint8[] public bonusPctSteps;
    
    function BCSAddBonusCrowdsale(        
        ITokenPool _tokenPool,
        IInvestRestrictions _restrictions,
        address _beneficiary, 
        uint256 _startTime, 
        uint256 _durationInHours, 
        uint256 _goalInWei,
        uint256 _tokensForOneEther,
        uint256 _bonusPct,
        uint256 _maxDecreasePct,        
        uint256 _decreaseStepPct,
        uint256 _stepDurationDays,
        uint256[] _investSteps,
        uint8[] _bonusPctSteps              
        ) 
        BCSCrowdsale(
            _tokenPool,
            _restrictions,
            _beneficiary, 
            _startTime, 
            _durationInHours, 
            _goalInWei,
            _tokensForOneEther,
            _bonusPct
        )
    {
        require (_bonusPct >= maxDecreasePct);

        investSteps = _investSteps;
        bonusPctSteps = _bonusPctSteps;
        maxDecreasePct = _maxDecreasePct;
        decreaseStepPct = _decreaseStepPct;
        stepDuration = _stepDurationDays * 1 days;
    }

    function getCurrentBonusPct(uint256 investment) public constant returns (uint256) {
        
        uint256 decreasePct = decreaseStepPct * (now - startTime) / stepDuration;
        if (decreasePct > maxDecreasePct) {
            decreasePct = maxDecreasePct;
        }

        uint256 first24hAddition = (now - startTime < 1 days ? 1 : 0);

        for (int256 i = int256(investSteps.length) - 1; i >= 0; --i) {
            if (investment >= investSteps[uint256(i)]) {
                return bonusPct - decreasePct + bonusPctSteps[uint256(i)] + first24hAddition;
            }
        }
                
        return bonusPct - decreasePct + first24hAddition;
    }

    //manually finishes crowdsale if 'true', or enables it again if 'false'
    // function finishCrowdsale(bool state) public managerOnly {
    //     if (state) {
    //         endTime = 1;            
    //     } else {
    //         endTime = 0;
    //     }
    // }
}
