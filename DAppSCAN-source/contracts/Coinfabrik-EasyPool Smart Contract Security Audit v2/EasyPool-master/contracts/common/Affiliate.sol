pragma solidity ^0.4.24;

import "../abstract/IAffiliate.sol";
//import "../zeppelin/SafeMath.sol";
import "./Restricted.sol";


/**
 * @title Affiliation Service
 */
contract Affiliate is IAffiliate, Restricted {
    // We could use SafeMath to catch errors in the logic, 
    // but if there are no such errors we can skip it.
    // using SafeMath for uint;  

    /**
     * @dev Affiliate structure.
     */
    struct AffiliateData {        
        uint currentBalance;
        uint totalRevenue;
        uint modelIndex;    
        uint curShare;        
        uint curLevel;        
        bool exists;
    }

    /**
     * @dev Subscriber structure.
     */
    struct SubscriberData {        
        uint generatedRevenue;
        uint transfersCount;        
    }  

    /**
     * @dev Revenue sharing rule.
     */    
    struct ShareRule {
        uint totalRevenue;
        uint sharePerEther;        
    }
    
    address[] public affiliates;
    address[] public subscribers;    

    mapping (address => address) public subToAffiliate;
    mapping (address => address[]) public affiliateToSubs;   
    mapping (address => AffiliateData) public affiliateToData;
    mapping (address => SubscriberData) public subscriberToData;                     
    mapping (uint => ShareRule[]) public models;    
    uint public curModelIndex = 0;   
    
    /**
     * @dev Constructor.
     */
    constructor() public {
        models[curModelIndex]
            .push(ShareRule(uint256MaxValue(), 0));
    }

    /**
     * @dev Update revenue sharing rules.
     */
    function setRevenueSharingRules(uint[] levels, uint[] shares) external onlyOwner {    
        require(levels.length > 0 && levels.length == shares.length);

        curModelIndex++;
        ShareRule[] storage rules = models[curModelIndex];                

        for (uint i = 0; i < levels.length; i++) {
            require(shares[i] <= 1 ether);
            rules.push(ShareRule(levels[i], shares[i]));
        }        
            
        emit RevenueSharingRulesChanged(
            levels, 
            shares,             
            curModelIndex
        );
    }

    /**
     * @dev Confirm or update affiliation.     
     */
    function confirmAffiliation() external {
        AffiliateData storage aData = affiliateToData[msg.sender];

        if(aData.exists) {
            require(aData.modelIndex != curModelIndex);
            aData.modelIndex = curModelIndex;  
            updateLevelAndShare(aData);
        } else {                     
            affiliates.push(msg.sender);
            aData.modelIndex = curModelIndex;   
            aData.curShare = models[curModelIndex][0].sharePerEther;
            aData.curLevel = models[curModelIndex][0].totalRevenue;              
            aData.exists = true;        
        }        
        
        emit AffiliationConfirmed(
            msg.sender, 
            aData.modelIndex
        );
    }

    /**
    * @dev Confirm new subscription.
    */
    function confirmSubscription(address affiliate) external {        
        require(affiliate != address(0));
        require(affiliateToData[affiliate].exists);
        require(subToAffiliate[msg.sender] == address(0));
                                
        subscribers.push(msg.sender);
        subToAffiliate[msg.sender] = affiliate;
        affiliateToSubs[affiliate].push(msg.sender);         

        emit SubscriptionConfirmed(
            affiliate, 
            msg.sender
        );
    }

    /**
    * @dev Withdraw available balance.
    */
    function withdraw() external {        
        uint amount = affiliateToData[msg.sender].currentBalance;         
        affiliateToData[msg.sender].currentBalance = 0;
        msg.sender.transfer(amount);
        emit Withdrawal(
            msg.sender, 
            amount
        );
    } 

    /**
    * @dev Send revenue share for specified subscriber.
    */
    function sendRevenueShare(address subscriber) external payable onlyOperator {
        require(msg.value > 0);
        require(subscriber != address(0));
        require(subToAffiliate[subscriber] != address(0));
                
        AffiliateData storage aData = affiliateToData[subToAffiliate[subscriber]];                
        aData.currentBalance += msg.value;  
        aData.totalRevenue += msg.value;

        if(aData.totalRevenue >= aData.curLevel) {
            updateLevelAndShare(aData);
        }
        
        SubscriberData storage sData = subscriberToData[subscriber];        
        sData.generatedRevenue += msg.value;
        sData.transfersCount++;

        emit RevenueShareReceived(
            subToAffiliate[subscriber], 
            subscriber,
            aData.currentBalance,
            msg.value            
        );
    }

    /**
     * @dev Update level and share for specified affiliate.
     */
    function updateLevelAndShare(AffiliateData storage aData) private {
        ShareRule[] storage rules = models[aData.modelIndex];  
        uint totalRevenue = aData.totalRevenue;

        uint length = rules.length;
        for (uint i = 0; i < length; i++) {
            if(totalRevenue < rules[i].totalRevenue) {
                aData.curShare = rules[i].sharePerEther;
                aData.curLevel = rules[i].totalRevenue;                
                return;
            }
        }

        aData.curLevel = uint256MaxValue();
    }


    /**
     * @dev Get revenue share for specified subscriber.     
     */
    function getSharePerEther(address subscriber) external view returns(uint sharePerEther, bool success) {
        if(subToAffiliate[subscriber] != address(0)) {
            AffiliateData storage aData = affiliateToData[subToAffiliate[subscriber]];                    
            sharePerEther = aData.curShare;
            success = true;
        }                        
    }
        
    /**
     * @dev Returns revenue sharing rules for specified model.
     */
    function getRevenueSharingRules(uint modelIndex) external view returns(uint[] levels, uint[] shares) {
        ShareRule[] storage rules = models[modelIndex];
        levels = new uint[](rules.length);
        shares = new uint[](rules.length);
        
        for (uint i = 0; i < rules.length; i++) {
            shares[i] = rules[i].sharePerEther;
            levels[i] = rules[i].totalRevenue;
        }            
    }        

    /**
     * @dev Returns list of all subscribers for specified affiliate. 
     */
    function getAffiliateSubscribers(address affiliate) external view returns(address[]) {
        return affiliateToSubs[affiliate];
    }

    /**
     * @dev Returns list of all subscribers. 
     */
    function getAllSubscribers() external view returns(address[]) {
        return subscribers;
    }

    /**
     * @dev Returns list of all affiliates. 
     */
    function getAllAffiliates() external view returns(address[]) {
        return affiliates;
    }

    /**
     * @dev Returns max value for uint256.
     */
    function uint256MaxValue() private pure returns(uint) {
        return 2**256 - 1;
    }
    
    event RevenueSharingRulesChanged(
        uint[] levels,
        uint[] shares,         
        uint index
    ); 
    event SubscriptionConfirmed(
        address indexed affiliate, 
        address subscriber
    );     
    event AffiliationConfirmed(
        address indexed affiliate, 
        uint indexed modelIndex
    );                  
    event RevenueShareReceived(
        address indexed affiliate, 
        address indexed subscriber, 
        uint affiliateBalance,
        uint amount
    ); 
    event Withdrawal(
        address indexed affiliate, 
        uint amount
    );           
}