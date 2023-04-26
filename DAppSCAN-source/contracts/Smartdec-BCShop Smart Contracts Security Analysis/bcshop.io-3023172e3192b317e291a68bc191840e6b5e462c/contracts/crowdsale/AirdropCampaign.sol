pragma solidity ^0.4.10;

import "../token/MintableToken.sol";
import "../common/Owned.sol";

contract AirdropCampaign is Owned {

    MintableToken public token;
    string public name;    
    uint32 public maxUnits;
    uint32 public soldUnits;
    uint8 public bronzeRewardTokens;
    uint8 public silverRewardTokens;
    uint8 public goldRewardTokens;
    uint8 public silverRewardDistance; //each x-th investor gets silver reward
    uint8 public goldRewardDistance; //each x-th investor gets gold reward
    bool public isActive;
    
    /**@dev List of buyers to prevent multiple purchases */
    mapping (address => uint256) public buyers;    

    //Triggers when all payments are successfully done
    //event ProductBought(address buyer, uint256 quantity, string clientId);

    function AirdropCampaign(
        MintableToken _token,
        string _name,
        uint32 _maxUnits,
        uint8 _bronzeReward,
        uint8 _silverReward,
        uint8 _goldReward,
        uint8 _silverDistance,
        uint8 _goldDistance,
        bool _active) {
        
        isActive = true;
        soldUnits = 0;
        token = _token;
        name = _name;
        maxUnits = _maxUnits;
        bronzeRewardTokens = _bronzeReward;
        silverRewardTokens = _silverReward;
        goldRewardTokens = _goldReward;
        silverRewardDistance = _silverDistance;
        goldRewardDistance = _goldDistance;
        isActive = _active;
    }

    function buy() {
        require(isActive && buyers[msg.sender] == 0 && soldUnits < maxUnits);    
        soldUnits++;

        uint256 tokenAmount = bronzeRewardTokens;
        if (soldUnits % goldRewardDistance == 0) {
            tokenAmount = goldRewardTokens;
        } else if (soldUnits % silverRewardDistance == 0) {
            tokenAmount = silverRewardTokens;
        }

        //tokenAmount = token.getRealTokenAmount(tokenAmount); //considering decimals

        token.mint(msg.sender, tokenAmount);
        buyers[msg.sender] = tokenAmount;        
    }    

    function setActive(bool state) ownerOnly {
        isActive = state;
    }
}