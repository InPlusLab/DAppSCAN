pragma solidity ^0.4.24;

import "./abstract/erc/IERC223Receiver.sol";
import "./library/ProPoolLib.sol";
import "./zeppelin/Math.sol";


/**
 * @title ProPool 
 */
contract ProPool is IERC223Receiver {
    using ProPoolLib for ProPoolLib.Pool;
    ProPoolLib.Pool pool;    

    /**
     * @dev Fallback.
     */
    function() external payable {
        pool.acceptRefundTransfer();
    }

    /**
     * @dev Constructor.
     */
    constructor(        
        uint maxBalance,
        uint minContribution,
        uint maxContribution,
        uint ctorFeePerEther,
        bool isRestricted,
        address creatorAddress,
        address presaleAddress,
        address feeServiceAddr,
        address[] whitelist,
        address[] admins
    ) public {
        pool.init(
            maxBalance,
            minContribution,
            maxContribution,
            ctorFeePerEther,
            isRestricted,                
            creatorAddress,
            presaleAddress,        
            feeServiceAddr,
            whitelist,
            admins
        );
    }    

    /**
     * @dev Redirect to pool library.
     */
    function setGroupSettings(                
        uint groupIndex,
        uint maxBalance,
        uint minContribution,
        uint maxContribution,
        uint ctorFeePerEther,         
        bool isRestricted
    ) external {
        pool.setGroupSettings(                
            groupIndex,
            maxBalance,
            minContribution,
            maxContribution,
            ctorFeePerEther,         
            isRestricted
        );
    }

    /**
     * @dev Redirect to pool library.
     */
    function cancel() external {
        pool.cancel();
    }

    /**
     * @dev Redirect to pool library.
     */
    function deposit(uint groupIndex) external payable {
        pool.deposit(groupIndex);
    }    

    /**
     * @dev Redirect to pool library.
     */
    function modifyWhitelist(uint groupIndex, address[] include, address[] exclude) external {
        pool.modifyWhitelist(groupIndex, include, exclude);
    }            

    /**
     * @dev Redirect to pool library.
     */
    function payToPresale(address presaleAddress, uint minPoolBalance, bool feeToToken, bytes data) external {
        pool.payToPresale(presaleAddress, minPoolBalance, feeToToken, data);
    }

    /**
     * @dev Redirect to pool library.
     */
    function lockPresaleAddress(address presaleAddress, bool lock) external {
        pool.lockPresaleAddress(presaleAddress, lock);
    }

    /**
     * @dev Redirect to pool library.
     */
    function confirmTokenAddress(address tokenAddress) external {
        pool.confirmTokenAddress(tokenAddress);
    }

    /**
     * @dev Redirect to pool library.
     */
    function setRefundAddress(address refundAddress) external {
        pool.setRefundAddress(refundAddress);
    }    

    /**
     * @dev Redirect to pool library.
     */
    function withdrawAmount(uint amount, uint groupIndex) external {
        pool.withdrawAmount(amount, groupIndex);
    }    

    /**
     * @dev Redirect to pool library.
     */
    function withdrawAll() external {
        pool.withdrawAll();
    }    

    /**
     * @dev Redirect to pool library.
     */
    function tokenFallback(address from, uint value, bytes data) public {
        pool.tokenFallback(from, value, data);
    }


    /**
     * @dev Redirect to pool library.
     */
    function getPoolDetails1() 
        external view 
        returns(
            uint libVersion,
            uint groupsCount,
            uint currentState,
            uint svcFeePerEther,
            bool feeToTokenMode,            
            address presaleAddress,
            address feeToTokenAddress,            
            address[] participants,
            address[] admins
        ) 
    {
        return pool.getPoolDetails1();
    }

    /**
     * @dev Redirect to pool library.
     */
    function getPoolDetails2() 
        external view 
        returns(                  
            uint refundBalance,                  
            address refundAddress,            
            address[] tokenAddresses,
            uint[] tokenBalances
        ) 
    {
        return pool.getPoolDetails2();
    }    

    /**
     * @dev Redirect to pool library.
     */
    function getParticipantDetails(address partAddress)
        external view 
        returns (
            uint[] contribution,
            uint[] remaining,
            bool[] whitelist,
            bool isAdmin,
            bool exists
        )     
    {
        return pool.getParticipantDetails(partAddress);
    }

    /**
     * @dev Redirect to pool library.
     */
    function getParticipantShares(address partAddress) 
        external view
        returns (
            uint[] tokenShare,
            uint refundShare            
        ) 
    {        
        return pool.getParticipantShares(partAddress);     
    }

    /**
     * @dev Redirect to pool library.
     */
    function getGroupDetails(uint groupIndex)
        external view 
        returns (
            uint contributionBalance,
            uint remainingBalance,
            uint maxBalance,
            uint minContribution,                 
            uint maxContribution,
            uint ctorFeePerEther,
            bool isRestricted,
            bool exists
        ) 
    {
        return pool.getGroupDetails(groupIndex);
    }    

    /**
     * @dev Redirect to pool library.
     */
    function getLibVersion() external pure returns(uint version) {
        version = ProPoolLib.version();
    }    

    event StateChanged(
        uint fromState,
        uint toState
    ); 

    event AdminAdded(
        address adminAddress
    );

    event WhitelistEnabled(
        uint groupIndex
    );

    event PresaleAddressLocked(
        address presaleAddress
    );  

    event RefundAddressChanged(
        address refundAddress
    );    

    event FeesDistributed(
        uint creatorFeeAmount,
        uint serviceFeeAmount
    );

    event IncludedInWhitelist(
        address participantAddress,
        uint groupIndex
    );

    event ExcludedFromWhitelist(
        address participantAddress,
        uint groupIndex
    );  

    event FeeServiceAttached(
        address serviceAddress,
        uint feePerEther
    );    

    event TokenAddressConfirmed(
        address tokenAddress,
        uint tokenBalance
    ); 

    event RefundReceived(
        address senderAddress,
        uint etherAmount
    );    
 
    event Contribution(
        address participantAddress,
        uint groupIndex,
        uint etherAmount,
        uint participantContribution,
        uint groupContribution        
    );

    event Withdrawal(
        address participantAddress,
        uint groupIndex,
        uint etherAmount,
        uint participantContribution,
        uint participantRemaining,        
        uint groupContribution,
        uint groupRemaining
    );

    event TokenWithdrawal(
        address tokenAddress,
        address participantAddress,
        uint poolTokenBalance,
        uint tokenAmount,
        bool succeeded    
    );   

    event RefundWithdrawal(
        address participantAddress,
        uint contractBalance,
        uint poolRemaining,
        uint etherAmount
    );  

    event ContributionAdjusted(
        address participantAddress,
        uint participantContribution,
        uint participantRemaining,
        uint groupContribution,
        uint groupRemaining,
        uint groupIndex
    );
  
    event GroupSettingsChanged(
        uint index,
        uint maxBalance,                               
        uint minContribution,
        uint maxContribution,                        
        uint ctorFeePerEther,
        bool isRestricted                            
    );       

    event AddressTransfer(
        address destinationAddress,
        uint etherValue
    );

    event AddressCall(
        address destinationAddress,
        uint etherAmount,
        uint gasAmount,
        bytes data      
    );   

    event TransactionForwarded(
        address destinationAddress,
        uint etherAmount,
        uint gasAmount,
        bytes data
    );

    event ERC223Fallback(
        address tokenAddress,
        address senderAddress,
        uint tokenAmount,
        bytes data
    );    
}