pragma solidity ^0.4.24;

import "../abstract/erc/IERC20Base.sol";
import "../abstract/IFeeService.sol";
//import "../zeppelin/SafeMath.sol";
import "../zeppelin/Math.sol";
import "./QuotaLib.sol";


/**
 * @title Presale pool library
 */
library ProPoolLib {    
    using QuotaLib for QuotaLib.Storage;
    // We could use SafeMath to catch errors in the logic, 
    // but if there are no such errors we can skip it.
    // using SafeMath for uint;    

    /**
     * @dev Pool possible states.
     */
    enum State {
        Open,
        PaidToPresale,
        Distribution,        
        FullRefund,
        Canceled
    }

    /**
     * @dev Pool participation group structure. 
     * Every participation group of the pool is represented by a copy of this structure. 
     * This structure holds information about the group settings and its current state.
     */
    struct Group {

        // Total contribution balance of the group. Every time participant 
        // contributes to the group the value of this field will be increased 
        // by the amount of participant contribution.
        uint contribution;            

        // Total remaining balance of the group. Group settings can be changed 
        // by pool administrator during the pooling period. For example, the max balance
        // of the group or max contribution per address can be decreased. Because of this,
        // the contribution amount of the participants that have made their contribution 
        // before this changes can be moved from the contribution balance of the group
        // to remainig balance of the group, partially or completely.
        uint remaining;                   

        // The total contribution balance of the group cannot be greater than this value.
        uint maxBalance;

        // The min contribution per address must be equal or greater than this value.
        uint minContribution; 

        // The max contribution per address must be equal or less than this value.
        uint maxContribution;        

        // Administrator's commission in terms of "Fee per Ether".
        uint ctorFeePerEther;          

        // Indicates when the group is public or private. Public group means that 
        // any address can contribute to it. In case of a private group, only 
        // whitelisted addresses can contribute to the group.
        bool isRestricted;

        // Group existence indicator.
        bool exists;
    }

    /**
     * @dev Pool participant structrure.
     * Every participant in the pool is represented by a copy of this structure.
     * This structure holds information about participant and his contributions.
     */
    struct Participant {

        // Describes the participant's contribution balance in the each of the groups.
        uint[8] contribution;

        // Describes the participant's remaining balance in the each of the groups.
        uint[8] remaining;

        // Indicates when the participant is whitelisted in the certain group.
        bool[8] whitelist;  

        // Indicates when the participant is an administrator.
        bool isAdmin;

        // Participant existence indicator.
        bool exists;
    }    

    /**
     * @dev Pool structure.
     * Every pool is represented by a copy of this structure. Holds information 
     * about current state of the pool, its participation groups and participants.
     */
    struct Pool {

        // Current state of the pool.
        State state;

        // EasyPool commission in terms of "Fee per Ether".
        // Is set only once, during pool creation transaction.
        uint svcFeePerEther;

        // Refund sender address. 
        // The pool refund transactions must be sent from this address.        
        address refundAddress;

        // Pool funds destionation address.
        // If locked the pool funds can only be sent to this address. 
        // Can be set only once by pool admin and can't be changed later.
        address presaleAddress;

        // Presale address can be locked.
        bool lockPresale;

        // FeeService contract interface.
        IFeeService feeService;

        // When paying to the presale "Fee-to-Token" mode can be chosen by admin. 
        // In this mode, the pool creator commission will be sent to the presale
        // as a part of creator contribution. 
        address feeToTokenAddress;        
        bool feeToTokenMode;
                  
        // Pool administrators array.
        address[] admins;

        // Pool participatnts array.
        address[] participants;     

        // Confirmed tokens array.
        address[] tokenAddresses;

        // Pool groups array.
        Group[8] groups;         

        // Mapping from participant address to the corresponding structure.
        mapping(address => Participant) participantToData;   

        // Mapping from token address to the corresponding quota storage.     
        mapping(address => QuotaLib.Storage) tokenQuota;  

        // Quota storage for pool refund balace.
        QuotaLib.Storage refundQuota;
    }                     

    /**
     * @dev Access modifier for admin-only functionality.
     */
    modifier onlyAdmin(Pool storage pool) {
        require(pool.participantToData[msg.sender].isAdmin);
        _;
    }

    /**
     * @dev Access modifier for in-state-only functionality.
     */
    modifier onlyInState(Pool storage pool, State state) {
        require(pool.state == state);
        _;
    }      

    /**
     * @dev Access modifier for in-state-only functionality.
     */
    modifier onlyInStates2(Pool storage pool, State state1, State state2) {
        require(pool.state == state1 || pool.state == state2);
        _;
    }  

    /**
     * @dev Access modifier for in-state-only functionality.
     */
    modifier onlyInStates3(Pool storage pool, State state1, State state2, State state3) {
        require(pool.state == state1 || pool.state == state2 || pool.state == state3);
        _;
    }    

    /**
     * @dev Setting new pool instance. Called when new pool is created.     
     */
    function init(
        Pool storage pool,           
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
    )
        public 
    {

        // Set presale address.
        if(presaleAddress != address(0)) {
            require(presaleAddress != address(this)); 
            pool.presaleAddress = presaleAddress;           
            emit PresaleAddressLocked(presaleAddress);            
        }
                
        // Set fee service contract.
        pool.feeService = IFeeService(feeServiceAddr);        
        pool.svcFeePerEther = pool.feeService.getFeePerEther();
        require(pool.svcFeePerEther <= (1 ether / 4));
        emit FeeServiceAttached(
            feeServiceAddr,
            pool.svcFeePerEther
        );  
        
        // Set pool administrators.
        require(creatorAddress != address(0));
        addAdmin(pool, creatorAddress);
        for(uint i = 0; i < admins.length; i++) {
            addAdmin(pool, admins[i]);
        }
        
        // Create first group.
        setGroupSettingsCore(
            pool,
            0,
            maxBalance,
            minContribution,
            maxContribution,
            ctorFeePerEther,
            isRestricted            
        );
        
        // Set whitelist.
        if(whitelist.length > 0) {
            require(isRestricted);
            modifyWhitelistCore(pool, 0, whitelist, new address[](0));
        }
    }

    /**
     * @dev Creates new participation group in case it doesn't exist 
     * or updates participation group settings in case the group exists.
     */
    function setGroupSettings(
        Pool storage pool,        
        uint idx,
        uint maxBalance,
        uint minContribution,
        uint maxContribution,
        uint ctorFeePerEther,         
        bool isRestricted
    )
        public     
        onlyAdmin(pool)
        onlyInState(pool, State.Open)      
    {
        // Group existence state.
        bool exists = pool.groups[idx].exists;

        // Set or update group settings.
        setGroupSettingsCore(
            pool,
            idx,
            maxBalance,
            minContribution,
            maxContribution,
            ctorFeePerEther,
            isRestricted            
        );
                
        if(exists) {            
            // Execute rebalancing.
            groupRebalance(pool, idx);
        }
    }

    /**
     * @dev Modify group whitelist.
     */
    function modifyWhitelist(Pool storage pool, uint idx, address[] include, address[] exclude)
        public 
        onlyAdmin(pool)
        onlyInState(pool, State.Open)
    {
        // Modify whitelist (without relabancing).
        modifyWhitelistCore(pool, idx, include, exclude); 
        // Execute group rebalancing.
        groupRebalance(pool, idx);
    }     

    /**
     * @dev Lock presale address.
     */
    function lockPresaleAddress(Pool storage pool, address presaleAddress, bool lock)
        public 
        onlyAdmin(pool) 
        onlyInState(pool, State.Open) 
    {        
        require(presaleAddress != address(0));
        require(presaleAddress != address(this));
        require(pool.presaleAddress == address(0));
        require(!pool.lockPresale);

        // Set presale address.
        pool.presaleAddress = presaleAddress;

        // Lock presale address.
        if(lock) {
            pool.lockPresale = true;
        }

        emit PresaleAddressLocked(presaleAddress);
    }   

    /**
     * @dev Confirm token address.
     */
    function confirmTokenAddress(Pool storage pool, address tokenAddress)
        public
        onlyAdmin(pool)
        onlyInStates2(pool, State.PaidToPresale, State.Distribution)         
    {        
        require(tokenAddress != address(0));
        require(pool.tokenAddresses.length <= 4);
        require(!contains(pool.tokenAddresses, tokenAddress));

        // Get token balance for the pool address.
        IERC20Base ERC20 = IERC20Base(tokenAddress);
        uint balance = ERC20.balanceOf(address(this));  

        // When confirming the token balance must be greater than zero.      
        require(balance > 0);

        // Change state of the pool if this is the first token confirmation.
        if(pool.state == State.PaidToPresale) {
            changeState(pool, State.Distribution);            
            sendFees(pool);
        } 
                        
        // Save token address.
        pool.tokenAddresses.push(tokenAddress);

        emit TokenAddressConfirmed(
            tokenAddress,
            balance
        );
    }

    /**
     * @dev Set refund sender address.
     */
    function setRefundAddress(Pool storage pool, address refundAddress)
        public
        onlyAdmin(pool)
        onlyInStates3(pool, State.PaidToPresale, State.Distribution, State.FullRefund)
    {        
        require(refundAddress != address(0));
        require(pool.refundAddress != refundAddress);

        // Set refund sender address.
        pool.refundAddress = refundAddress;
        emit RefundAddressChanged(refundAddress);

        // This is full refund scenario.
        if(pool.state == State.PaidToPresale) {
            changeState(pool, State.FullRefund);
        }
    }   

    /**
     * @dev Send pool balance to presale address.
     */
    function payToPresale(
        Pool storage pool,
        address presaleAddress,
        uint minPoolBalance,
        bool feeToToken,
        bytes data
    )
        public
        onlyAdmin(pool) 
        onlyInState(pool, State.Open) 
    {
        require(presaleAddress != address(0));
                        
        // Check if presale address is locked.
        if(pool.presaleAddress == address(0)) {
            pool.presaleAddress = presaleAddress;
            emit PresaleAddressLocked(presaleAddress);
        } else { 
            // If locked then destination address must be same.
            require(pool.presaleAddress == presaleAddress);
        }
        
        uint ctorFee;
        uint poolRemaining;
        uint poolContribution;      
        // Calculate pool summaries.          
        (poolContribution, poolRemaining, ctorFee) = calcPoolSummary(pool);        
        require(poolContribution > 0 && poolContribution >= minPoolBalance);

        // Set fee-to-token mode.
        if(feeToToken) {
            pool.feeToTokenMode = true;            
            pool.feeToTokenAddress = msg.sender;
            ctorFee = 0;
        }

        changeState(pool, State.PaidToPresale);

        // Transafer funds.
        addressCall(
            pool.presaleAddress,
            poolContribution - ctorFee - calcFee(poolContribution, pool.svcFeePerEther),
            data
        );        
    }

    /**
     * @dev Cancel pool.
     */
    function cancel(Pool storage pool)
        public
        onlyAdmin(pool) 
        onlyInState(pool, State.Open)
    {
        changeState(pool, State.Canceled);
    }  

    /**
     * @dev Contribute to the group.
     */
    function deposit(Pool storage pool, uint idx)
        public        
        onlyInState(pool, State.Open)  
    {
        require(msg.value > 0);
        require(pool.groups.length > idx);
        require(pool.groups[idx].exists);

        // Get group and participant instances.
        Participant storage participant = pool.participantToData[msg.sender];
        Group storage group = pool.groups[idx];        

        // Calculate contribution and remaining balance.
        uint remaining;
        uint contribution;                
        (contribution, remaining) = calcContribution(
            idx, 
            msg.value, 
            group.maxBalance, 
            group.contribution - participant.contribution[idx], 
            group.minContribution, 
            group.maxContribution, 
            group.isRestricted,            
            participant
        );

        // Remaining balance must be equal to zero.
        require(remaining == 0);

        // Set the participant existence state.
        if (!participant.exists) {
            participant.exists = true;   
            pool.participants.push(msg.sender);
        }        

        // Mark participant as whitelisted.
        if(!participant.whitelist[idx]) {
            participant.whitelist[idx] = true;         
        }

        // Update contribution and remaining balance.
        group.contribution = group.contribution - participant.contribution[idx] + contribution;
        group.remaining = group.remaining - participant.remaining[idx] + remaining;
        participant.contribution[idx] = contribution;
        participant.remaining[idx] = remaining;

        emit Contribution(
            msg.sender,
            idx,
            msg.value,
            contribution,
            group.contribution
        );        
    }

    /**
     * @dev Withdraw from the group.
     */     
    function withdrawAmount(Pool storage pool, uint amount, uint idx)
        public
        onlyInState(pool, State.Open)
    {
        // Get participant instance.
        Participant storage participant = pool.participantToData[msg.sender];                        
        uint finalAmount;
        
        if(amount == 0) {
            // If withdrawal amount is equal to zero then withdraw entire contribution.
            finalAmount = participant.contribution[idx] + participant.remaining[idx];
        } else {
            // Requested withdrawal amount must be equal or greater than participant 
            // remaining balance, but less or equal than his total contribution.
            require(amount >= participant.remaining[idx]);
            require(amount <= participant.contribution[idx] + participant.remaining[idx]);
            finalAmount = amount;
        }

        require(finalAmount > 0);
        
        // Get group instance.
        Group storage group = pool.groups[idx];

        // Update group remaining balance.
        group.remaining -= participant.remaining[idx];        

        // Check if withdrawal amount is greater than remaining balance.
        uint extra = finalAmount - participant.remaining[idx];        

        // Update participant remaining balance. At this point always zero.
        participant.remaining[idx] = 0;        

        if(extra > 0) {
            // Update group and participant contribution balance.
            participant.contribution[idx] -= extra;
            group.contribution -= extra;            

            if(!participant.isAdmin) {
                // Make sure that requested withdrawal amount won't break group settings.
                require(participant.contribution[idx] >= group.minContribution);
            }
        }

        // Transfer funds.
        addressTransfer(msg.sender, finalAmount);

        emit Withdrawal(
            msg.sender,
            finalAmount,
            participant.contribution[idx],
            0,
            group.contribution,
            group.remaining,
            idx
        );                        
    } 

    /**
     * @dev Wihdraw 'All-in-One' function (public wrapper).     
     */ 
    function withdrawAll(Pool storage pool) public {

        // Withdraw refund share and tokens share.
        if (pool.state == State.FullRefund || pool.state == State.Distribution) {
            withdrawRefundAndTokens(pool);
            return;
        }
        
        // Withdraw entire contribution balance.
        if(pool.state == State.Canceled || pool.state == State.Open) {
            withdrawAllContribution(pool);
            return;
        }            
        
        // Withdraw remaining balance.
        if (pool.state == State.PaidToPresale) {
            withdrawAllRemaining1(pool);
            return;
        } 

        // Revert transaction.
        revert();
    }

    /**
     * @dev ERC223 fallback.
     */
    function tokenFallback(Pool storage pool, address from, uint value, bytes data)
        public 
        onlyInStates2(pool, State.PaidToPresale, State.Distribution)
    {
        emit ERC223Fallback(
            msg.sender,
            from,
            value,
            data
        );
    }    

    /**
     * @dev Accept refund transfer.     
     */
    function acceptRefundTransfer(Pool storage pool)
        public 
        onlyInStates2(pool, State.Distribution, State.FullRefund)  
    {
        require(msg.value > 0);
        require(msg.sender == pool.refundAddress);

        emit RefundReceived(
            msg.sender, 
            msg.value
        );
    }  

    /**
     * @dev Returns pool details (part #1).
     */
    function getPoolDetails1(Pool storage pool) 
        public view 
        returns (     
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
        libVersion = version();
        currentState = uint(pool.state);
        groupsCount = pool.groups.length;
        svcFeePerEther = pool.svcFeePerEther;
        feeToTokenMode = pool.feeToTokenMode;        
        presaleAddress = pool.presaleAddress;
        feeToTokenAddress = pool.feeToTokenAddress;        
        participants = pool.participants;
        admins = pool.admins;
    }  

    /**
     * @dev Returns pool details (part #2).
     */
    function getPoolDetails2(Pool storage pool) 
        public view 
        returns (      
            uint refundBalance,
            address refundAddress,
            address[] tokenAddresses,
            uint[] tokenBalances
        )
    {                                                
        if(pool.state == State.Distribution || pool.state == State.FullRefund) {                 
            uint poolRemaining;
            (,poolRemaining,) = calcPoolSummary(pool);
            refundBalance = address(this).balance - poolRemaining;
            refundAddress = pool.refundAddress;
            
            tokenAddresses = pool.tokenAddresses;
            tokenBalances = new uint[](tokenAddresses.length);
            for(uint i = 0; i < tokenAddresses.length; i++) {
                tokenBalances[i] = IERC20Base(tokenAddresses[i]).balanceOf(address(this));
            }
        }
    }

    /**
     * @dev Returns participant details.
     */
    function getParticipantDetails(Pool storage pool, address addr)
        public view 
        returns (
            uint[] contribution,
            uint[] remaining,
            bool[] whitelist,
            bool isAdmin,
            bool exists
        ) 
    {
        Participant storage part = pool.participantToData[addr];
        isAdmin = part.isAdmin;                
        exists = part.exists;

        uint length = pool.groups.length;
        contribution = new uint[](length);
        remaining = new uint[](length);
        whitelist = new bool[](length);        

        for(uint i = 0; i < length; i++) {
            contribution[i] = part.contribution[i];
            remaining[i] = part.remaining[i];
            whitelist[i] = part.whitelist[i];
        }                      
    }        

    /**
     * @dev Returns participant shares.
     */
    function getParticipantShares(Pool storage pool, address addr) public view returns (uint[] tokenShare, uint refundShare) {       
        if(pool.state == State.Distribution || pool.state == State.FullRefund) {
            uint netPoolContribution;
            uint netPartContribution;
            uint poolRemaining;
            uint poolCtorFee;   

            (netPoolContribution, netPartContribution, poolRemaining, poolCtorFee) = calcPoolSummary3(pool, addr);
            tokenShare = new uint[](pool.tokenAddresses.length);

            if(netPartContribution > 0) {
                refundShare = pool.refundQuota.calcShare(
                    addr, 
                    address(this).balance - poolRemaining,
                    [netPartContribution, netPoolContribution]
                );        
            }     

            if(pool.feeToTokenMode) {
                netPoolContribution += poolCtorFee;
                if(pool.feeToTokenAddress == addr) {
                    netPartContribution += poolCtorFee;
                }
            }  

            if(netPartContribution > 0) {
                for(uint i = 0; i < pool.tokenAddresses.length; i++) {
                    tokenShare[i] = pool.tokenQuota[pool.tokenAddresses[i]].calcShare(
                        addr,
                        IERC20Base(pool.tokenAddresses[i]).balanceOf(address(this)),
                        [netPartContribution, netPoolContribution]
                    );                
                }      
            }
        }  
    }    

    /**
     * @dev Returns group details.
     */
    function getGroupDetails(Pool storage pool, uint idx)
        public view 
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
        Group storage group = pool.groups[idx];                                                
        contributionBalance = group.contribution;
        remainingBalance = group.remaining;
        maxBalance = group.maxBalance;
        minContribution = group.minContribution;
        maxContribution = group.maxContribution;
        ctorFeePerEther = group.ctorFeePerEther;
        isRestricted = group.isRestricted;
        exists = group.exists;
    }       

    /**
     * @dev Returns library version.
     */
    function version() public pure returns (uint) {
        // type: 100 
        // major: 100
        // minor: 100        
        return 100100101;
    }    

    /**
     * @dev Withdraw entire contribution balance.
     */     
    function withdrawAllContribution(Pool storage pool) private {        
        Participant storage participant = pool.participantToData[msg.sender];
        Group storage group;
        uint contribution;  
        uint remaining;
        uint amount;
        uint sum;

        // Iterate through the groups.
        uint length = pool.groups.length;
        for(uint idx = 0; idx < length; idx++) {

            // Read contribution and remaining balance.
            contribution = participant.contribution[idx];
            remaining = participant.remaining[idx];
            sum = contribution + remaining;

            if(sum > 0) {
                amount += sum;
                group = pool.groups[idx];

                // Reset contribution balance.
                if(contribution > 0) {                    
                    group.contribution -= contribution;
                    participant.contribution[idx] = 0;
                }

                // Reset remaining balance.
                if(remaining > 0) {
                    group.remaining -= remaining;
                    participant.remaining[idx] = 0;
                }
                                       
                emit Withdrawal(
                    msg.sender,
                    idx,
                    sum,
                    0,
                    0,
                    group.contribution,
                    group.remaining                    
                );
            }
        }

        // Transfer funds.
        require(amount > 0);
        addressTransfer(
            msg.sender, 
            amount
        );
    }

    /**
     * @dev Wihdraw remaining balance (simple).
     */  
    function withdrawAllRemaining1(Pool storage pool) private {
        Participant storage participant = pool.participantToData[msg.sender];        
        Group storage group;
        uint remaining;
        uint amount;
        
        // Iterate through the groups.
        uint length = pool.groups.length;
        for(uint idx = 0; idx < length; idx++) {            
            remaining = participant.remaining[idx];

            // Reset remaining balance.
            if(remaining > 0) {
                amount += remaining;
                group = pool.groups[idx];
                group.remaining -= remaining;        
                participant.remaining[idx] = 0;                                

                emit Withdrawal(
                    msg.sender,
                    idx,
                    remaining,
                    participant.contribution[idx],
                    0,
                    group.contribution,
                    group.remaining
                );
            }
        }

        // Transfer funds.
        require(amount > 0);
        addressTransfer(
            msg.sender, 
            amount
        );
    }

    /**
     * @dev Wihdraw remaining balance and calculate.
     */  
    function withdrawAllRemaining2(Pool storage pool) 
        private 
        returns
    (
        uint poolContribution,
        uint poolRemaining,
        uint poolCtorFee,
        uint partContribution,        
        uint partCtorFee
    ) 
    {
        Participant storage participant = pool.participantToData[msg.sender];
        Group storage group;
        uint sumRemaining; 
        uint remaining;     

        // Iterate through the groups.
        uint length = pool.groups.length;
        for(uint idx = 0; idx < length; idx++) {                        
            group = pool.groups[idx];

            // Make required calculations.
            poolRemaining += group.remaining;
            poolContribution += group.contribution;
            poolCtorFee += calcFee(group.contribution, group.ctorFeePerEther);
            
            // Make required calculations.
            remaining = participant.remaining[idx];
            partContribution += participant.contribution[idx];
            partCtorFee += calcFee(participant.contribution[idx], group.ctorFeePerEther);

            // Reset remaining balance.
            if(remaining > 0) {              
                sumRemaining += remaining;                            
                group.remaining -= remaining;
                participant.remaining[idx] = 0;  

                emit Withdrawal(
                    msg.sender,
                    idx,
                    remaining,
                    participant.contribution[idx],
                    0,
                    group.contribution,
                    group.remaining                    
                );
            }
        }

        // Transfer funds.
        if(sumRemaining > 0) {
            poolRemaining -= sumRemaining;
            addressTransfer(msg.sender, sumRemaining);
        }
    }    
    
    /**
     * @dev Withdarw refund share and tokens share.
     */  
    function withdrawRefundAndTokens(Pool storage pool) private {
        uint poolContribution;
        uint poolRemaining;
        uint poolCtorFee;
        uint partContribution;        
        uint partCtorFee;

        // Withdraw remaining balance.
        (poolContribution, 
            poolRemaining, 
            poolCtorFee, 
            partContribution,             
            partCtorFee
        ) = withdrawAllRemaining2(pool);

        // Calculate net contribution values.        
        uint netPoolContribution = poolContribution - poolCtorFee - calcFee(poolContribution, pool.svcFeePerEther);
        uint netPartContribution = partContribution - partCtorFee - calcFee(partContribution, pool.svcFeePerEther);
        
        if(netPartContribution > 0) {
            // Withdraw refund share based on net contribution.
            withdrawRefundShare(pool, poolRemaining, netPoolContribution, netPartContribution);
        }

        // 'Fee-to-Token' mode.
        if(pool.feeToTokenMode) {
            netPoolContribution += poolCtorFee;
            if(pool.feeToTokenAddress == msg.sender) {
                netPartContribution += poolCtorFee;
            }
        }

        if(netPartContribution > 0) {
            // Withdraw tokens share based on net contribution.
            withdrawTokens(pool, netPoolContribution, netPartContribution);
        }
    }

    /**
     * @dev Withdarw refund share.
     */
    function withdrawRefundShare(
        Pool storage pool, 
        uint poolRemaining,
        uint netPoolContribution, 
        uint netPartContribution
    )
        private 
    {
        if(address(this).balance > poolRemaining) {
            // Calculate and claim refund share.
            uint amount = pool.refundQuota.claimShare(
                msg.sender, 
                address(this).balance - poolRemaining,
                [netPartContribution, netPoolContribution]
            );

            if(amount > 0) {          
                // Trunsfer funds.                      
                addressTransfer(msg.sender, amount);
                emit RefundWithdrawal(
                    msg.sender,
                    address(this).balance,
                    poolRemaining,
                    amount
                );                
            }
        }
    }

    /**
     * @dev Withdraw tokens share.
     */
    function withdrawTokens(
        Pool storage pool,        
        uint netPoolContribution,
        uint netPartContribution
    )
        private 
    {
        bool succeeded;
        uint tokenAmount;
        uint tokenBalance;
        address tokenAddress;
        IERC20Base tokenContract;
        QuotaLib.Storage storage quota;

        // Iterate through the token addresses.
        uint length = pool.tokenAddresses.length;
        for(uint i = 0; i < length; i++) {             

            tokenAddress = pool.tokenAddresses[i];            
            tokenContract = IERC20Base(tokenAddress); 
            // Get token balance for the pool address.
            tokenBalance = tokenContract.balanceOf(address(this));

            if(tokenBalance > 0) {    
                // Calculate and claim the token share.                                    
                quota = pool.tokenQuota[tokenAddress];
                tokenAmount = quota.claimShare(
                    msg.sender,
                    tokenBalance, 
                    [netPartContribution, netPoolContribution]
                ); 

                if(tokenAmount > 0) {
                    // Try to transfer tokens.
                    succeeded = tokenContract.transfer(msg.sender, tokenAmount);
                    if (!succeeded) {                        
                        quota.undoClaimShare(msg.sender, tokenAmount);
                    }
                    emit TokenWithdrawal(
                        tokenAddress,
                        msg.sender,
                        tokenBalance,
                        tokenAmount,
                        succeeded
                    );
                }
            }
        } 
    }   

    /**
     * @dev Create new participation group in case it doesn't exist otherwise update its settings.     
     */
    function setGroupSettingsCore(
        Pool storage pool,        
        uint idx,
        uint maxBalance,
        uint minContribution,
        uint maxContribution,
        uint ctorFeePerEther,         
        bool isRestricted
    )
        private             
    {
        require(pool.groups.length > idx);
        Group storage group = pool.groups[idx];        
        
        if(!group.exists) {
            // Create new group. Pool groups should be created one-by-one.
            require(idx == 0 || pool.groups[idx - 1].exists);
            group.exists = true;
        }
        
        validateGroupSettings(
            maxBalance, 
            minContribution, 
            maxContribution
        );        
        
        if(group.maxBalance != maxBalance) {
            group.maxBalance = maxBalance;  
        }          
        
        if(group.minContribution != minContribution) {
            group.minContribution = minContribution;
        }

        if(group.maxContribution != maxContribution) {
            group.maxContribution = maxContribution;
        }
        
        if(group.ctorFeePerEther != ctorFeePerEther) {
            require(ctorFeePerEther <= (1 ether / 2));
            group.ctorFeePerEther = ctorFeePerEther;
        }
        
        if(group.isRestricted != isRestricted) {
            group.isRestricted = isRestricted;  
        }      

        emit GroupSettingsChanged(
            idx,
            maxBalance,
            minContribution,
            maxContribution,
            ctorFeePerEther,
            isRestricted
        );                             
    }    

    /**
     * @dev Modify group whitelist.
     */
    function modifyWhitelistCore(Pool storage pool, uint idx, address[] include, address[] exclude) private {
        require(include.length > 0 || exclude.length > 0);
        require(pool.groups.length > idx && pool.groups[idx].exists);

        // Get group and participant instances.
        Group storage group = pool.groups[idx];
        Participant storage participant;        
        uint i;

        // Mark group as restricted.
        if(!group.isRestricted) {
            group.isRestricted = true;
            emit WhitelistEnabled(idx);
        }    

        // Exclude participants.
        for(i = 0; i < exclude.length; i++) {
            participant = pool.participantToData[exclude[i]];            
            if(participant.whitelist[idx]) {
                participant.whitelist[idx] = false;
                emit ExcludedFromWhitelist(
                    exclude[i],
                    idx
                );                
            }
        }

        // Include participants.
        for(i = 0; i < include.length; i++) {
            participant = pool.participantToData[include[i]];  

            if(!participant.whitelist[idx]) { 
                // Create new participant.
                if (!participant.exists) {                    
                    pool.participants.push(include[i]);
                    participant.exists = true;                                        
                }                        

                // Set as whitelisted.
                participant.whitelist[idx] = true;               
                emit IncludedInWhitelist(
                    include[i],
                    idx
                );
            }                
        }
    }        

    /**
     * @dev Distribute fees. When calling this function, contract balance should
     *  consist of participants remaining balance, creator commission and service commission.
     */
    function sendFees(Pool storage pool) private {
        uint ctorFee;
        uint poolRemaining;
        uint poolContribution;
        // Calculate and transfer creator fee.
        (poolContribution, poolRemaining, ctorFee) = calcPoolSummary(pool);
        if(ctorFee > 0 && !pool.feeToTokenMode) {
            addressTransfer(msg.sender, ctorFee);            
        }
        
        // Calculate and transfer service fee.
        uint svcFee = address(this).balance - poolRemaining;        
        if(svcFee > 0) {
            address creator = getPoolCreator(pool);
            pool.feeService.sendFee.value(svcFee)(creator);
        }

        emit FeesDistributed(
            ctorFee,
            svcFee
        );
    }   

    /**
     * @dev Rebalance group contributions.
     */
    function groupRebalance(Pool storage pool, uint idx) private {
        Group storage group = pool.groups[idx];          
        uint maxBalance = group.maxBalance;
        uint minContribution = group.minContribution;    
        uint maxContribution = group.maxContribution;            
        bool isRestricted = group.isRestricted;        
        Participant storage participant;         
        uint groupContribution;
        uint groupRemaining;
        uint contribution;
        uint remaining;     
        uint x = idx;   

        // TODO: Getting stack too deep here..
        // uint length = pool.participants.length;
        for(uint i = 0; i < pool.participants.length; i++) {           
            participant = pool.participantToData[pool.participants[i]];                
            
            // Calculate contribution and remaining balance.
            (contribution, remaining) = calcContribution(       
                x,
                0,
                maxBalance,
                groupContribution,
                minContribution,
                maxContribution,
                isRestricted,
                participant
            );        

            // Save changes if some available.
            if(contribution != participant.contribution[x]) {
                participant.contribution[x] = contribution;
                participant.remaining[x] = remaining;
            }            
            
            groupContribution += contribution;            
            groupRemaining += remaining;

            emit ContributionAdjusted(
                pool.participants[i], 
                contribution,
                remaining,
                groupContribution,
                groupRemaining,
                x
            );
        }
        
        // Update group contribution and remaining balance.
        if(group.contribution != groupContribution) {
            group.contribution = groupContribution;             
            group.remaining = groupRemaining;           
        }  
    } 

    /**
     * @dev Change pool state.
     */
    function changeState(Pool storage pool, State state) private {
        assert(pool.state != state);
        emit StateChanged(
            uint(pool.state), 
            uint(state)
        );
        pool.state = state;        
    }

    /**
     * @dev Add pool admin.
     */
    function addAdmin(Pool storage pool, address admin) private {
        require(admin != address(0));
        Participant storage participant = pool.participantToData[admin];
        require(!participant.exists && !participant.isAdmin);

        participant.exists = true;
        participant.isAdmin = true;
        pool.participants.push(admin);
        pool.admins.push(admin);             
        
        emit AdminAdded(admin);                  
    }  

    /**
     * @dev Trusted transfer.
     */
    function addressTransfer(address destination, uint etherAmount) private {
        emit AddressTransfer(
            destination,
            etherAmount
        );
        destination.transfer(etherAmount);        
    }

    /**
     * @dev Untrasted call.
     */
    function addressCall(address destination, uint etherAmount, bytes data) private {
        addressCall(destination, 0, etherAmount, data);
    }

    /**
     * @dev Untrasted call.
     */
    function addressCall(address destination, uint gasAmount,  uint etherAmount, bytes data) private {
        emit AddressCall(
            destination,
            etherAmount,
            gasAmount > 0 ? gasAmount : gasleft(),
            data
        );
        require(
            destination.call
            .gas(gasAmount > 0 ? gasAmount : gasleft())
            .value(etherAmount)
            (data)            
        );
    }

    /**
     * @dev Calculate participant contribution.
     */
    function calcContribution(
        uint idx,
        uint amount,
        uint maxBalance,
        uint currentBalance,
        uint minContribution, 
        uint maxContribution,
        bool isRestricted,        
        Participant storage participant
    )
        private view 
        returns(uint contribution, uint remaining)
    {
        // Total contribution amount.
        uint totalAmount = participant.contribution[idx]
            + participant.remaining[idx]
            + amount;

        // There are no limitations for admins.
        if(participant.isAdmin) {
            contribution = totalAmount;
            return;
        }                

        // Limitations on group max balance & whitelist.
        if(currentBalance >= maxBalance || (isRestricted && !participant.whitelist[idx])) {
            remaining = totalAmount;            
            return;
        }        
                        
        contribution = Math.min(maxContribution, totalAmount);        
        contribution = Math.min(maxBalance - currentBalance, contribution);
        
        // Limitation on group min contribution.
        if(contribution < minContribution) {
            remaining = totalAmount;
            contribution = 0;
            return;
        }
                
        remaining = totalAmount - contribution;
    }

    /**
     * @dev Calculate pool summaries.
     */
    function calcPoolSummary(Pool storage pool) 
        private view 
        returns
    (
        uint poolContribution, 
        uint poolRemaining, 
        uint ctorFee
    ) 
    {
        Group storage group;
        uint length = pool.groups.length;

        for(uint idx = 0; idx < length; idx++) {
            group = pool.groups[idx];
            if(!group.exists) {
                break;
            }
            
            poolRemaining += group.remaining;
            poolContribution += group.contribution;            
            ctorFee += calcFee(group.contribution, group.ctorFeePerEther);
        }
    }  

    /**
     * @dev Calculate pool & participant summaries.
     */  
    function calcPoolSummary2(Pool storage pool, address addr) 
        private view
        returns
    (
        uint poolContribution,
        uint poolRemaining,
        uint poolCtorFee,
        uint partContribution,        
        uint partCtorFee
    ) 
    {
        Group storage group;
        Participant storage participant = pool.participantToData[addr];        
        uint length = pool.groups.length;
        
        for(uint idx = 0; idx < length; idx++) {            
            group = pool.groups[idx];
            if(!group.exists) {
                break;
            }

            poolRemaining += group.remaining;
            poolContribution += group.contribution;
            poolCtorFee += calcFee(group.contribution, group.ctorFeePerEther);
                        
            partContribution += participant.contribution[idx];
            partCtorFee += calcFee(participant.contribution[idx], group.ctorFeePerEther);
        }
    }     

    /**
     * @dev Calculate pool & participant net summaries.
     */   
    function calcPoolSummary3(Pool storage pool, address addr) 
        private view
        returns
    (
        uint netPoolContribution,
        uint netPartContribution,
        uint poolRemaining,
        uint poolCtorFee
    ) 
    {
        uint poolContribution;        
        uint partContribution;
        uint partCtorFee;

        (poolContribution, 
            poolRemaining, 
            poolCtorFee, 
            partContribution,             
            partCtorFee
        ) = calcPoolSummary2(pool, addr);

        netPoolContribution = poolContribution - poolCtorFee - calcFee(poolContribution, pool.svcFeePerEther);
        netPartContribution = partContribution - partCtorFee - calcFee(partContribution, pool.svcFeePerEther);
    }          
  
    /**
     * @dev Function for validating group settings.
     */
    function validateGroupSettings(uint maxBalance, uint minContribution, uint maxContribution) private pure {
        require(
            minContribution > 0 &&
            minContribution <= maxContribution &&
            maxContribution <= maxBalance &&
            maxBalance <= 1e9 ether            
        );
    }

    /**
     * @dev Check if an array contains provided value.
     */
    function contains(address[] storage array, address addr) private view returns (bool) {
        for (uint i = 0; i < array.length; i++) {
            if (array[i] == addr) {
                return true;
            }
        }
        return false;
    } 

    /**
     * @dev Returns pool creator address.
     */
    function getPoolCreator(Pool storage pool) private view returns(address) {
        return pool.admins[0];
    }     

    /**
     * @dev Fee calculator.
     */
    function calcFee(uint etherAmount, uint feePerEther) private pure returns(uint fee) {
        fee = (etherAmount * feePerEther) / 1 ether;
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