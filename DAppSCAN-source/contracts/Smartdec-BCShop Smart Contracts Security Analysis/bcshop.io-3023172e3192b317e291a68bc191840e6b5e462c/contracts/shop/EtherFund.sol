pragma solidity ^0.4.10;

import "../common/Owned.sol";
import "../common/SafeMath.sol";
import "./IFund.sol";

/**@dev This contract is used to split incoming ether in proportions between 2 or more receivers 
The share of each one is stored in sharePermille mapping.*/
contract EtherFund is Owned, SafeMath, IFund {

    event EtherWithdrawn(address indexed receiver, address indexed to, uint256 amount);
    event EtherReceived(address indexed sender, uint256 amount);
    event ReceiverChanged(address indexed oldOne, address indexed newOne);
    event ShareChanged(address indexed receiver, uint16 share);

    /**@dev The share of a specific address, in permille (1/1000) */
    mapping (address => uint16) public sharePermille;

    /**@dev Ether balance to withdraw */
    mapping (address => uint256) public etherBalance;

    /**@dev The contract balance at last claim (transfer or withdraw) */
    uint public lastBalance;

    /**@dev The totalDeposits at the time of last claim */
    mapping (address => uint256) public lastSumDeposits;
        
    /**@dev The summation of ether deposited up to when a receiver last triggered a claim */
    uint public sumDeposits;    

    // SWC-108-State Variable Default Visibility: L32 - L40
    function EtherFund(address receiver1, uint16 share1, address receiver2, uint16 share2) {
        // SWC-101-Integer Overflow and Underflow: L34
        require(share1 + share2 == 1000);

        sharePermille[receiver1] = share1;
        sharePermille[receiver2] = share2;

        ShareChanged(receiver1, share1);
        ShareChanged(receiver2, share2);
    }

    /**@dev allows to receive Ether */
    function () payable {
        EtherReceived(msg.sender, msg.value);
    }

    /**@dev Transfers all stored Ether to the new fund */
    function migrate(address newFund) public ownerOnly {
        newFund.transfer(this.balance);
    }

    /**@dev Copies internal state of another fund for specific receiver */
    function copyStateFor(EtherFund otherFund, address receiver) public ownerOnly {
        sharePermille[receiver] = otherFund.sharePermille(receiver);
        etherBalance[receiver] = otherFund.etherBalance(receiver);
        lastSumDeposits[receiver] = otherFund.lastSumDeposits(receiver);

        lastBalance = otherFund.lastBalance();
        sumDeposits = otherFund.sumDeposits();
    }

    /**@dev Returns total ether deposits to date */
    function deposits() public constant returns (uint) {
        return safeAdd(sumDeposits, safeSub(this.balance, lastBalance));
    }

    /**@dev Returns how much ether can be claimed */
    function etherBalanceOf(address receiver) public constant returns (uint) {
        return safeAdd(etherBalance[receiver], claimableEther(receiver));
    }   
    
    /**@dev Withdraw share. Throws on failure */
    function withdraw(uint amount) public {
        withdrawTo(msg.sender, amount);
    }

    function withdrawTo(address to, uint amount) public {
        update(msg.sender);
        
        // check balance and withdraw on valid amount
        require(amount <= etherBalance[msg.sender]);

        etherBalance[msg.sender] = safeSub(etherBalance[msg.sender], amount);
        lastBalance = safeSub(lastBalance, amount);
                
        EtherWithdrawn(msg.sender, to, amount);
        to.transfer(amount);        
    }    

    /**@dev Changes receiver to the new one */
    function changeReceiver(address oldReceiver, address newReceiver) 
        public
        ownerOnly
    {
        sharePermille[newReceiver] = sharePermille[oldReceiver];
        sharePermille[oldReceiver] = 0;

        etherBalance[newReceiver] = etherBalance[oldReceiver];
        etherBalance[oldReceiver] = 0;

        lastSumDeposits[newReceiver] = lastSumDeposits[oldReceiver];
        lastSumDeposits[oldReceiver] = 0;

        ReceiverChanged(oldReceiver, newReceiver);
    }

    /**@dev Changes the share of 2 given addresses. 
    Requires 2 addresses: increased and decreased, to ensure that sum of shares is unchanged  */
    function changeShares(address receiver1, uint16 share1, address receiver2, uint16 share2)
        public 
        ownerOnly
    {
        //check the input parameters, sum should be unchanged
        require(share1 + share2 == sharePermille[receiver1] + sharePermille[receiver2]);

        update(receiver1);
        update(receiver2);

        sharePermille[receiver1] = share1;
        sharePermille[receiver2] = share2;

        ShareChanged(receiver1, share1);
        ShareChanged(receiver2, share2);        
    }

    /**@dev Changes the share of 3 given addresses. 
    Requires 3 addresses, to ensure that sum of shares is unchanged  */
    function changeShares3(address receiver1, uint16 share1, address receiver2, uint16 share2, address receiver3, uint16 share3)
        public 
        ownerOnly
    {
        //check the input parameters, sum should be unchanged
        require(share1 + share2 + share3 == sharePermille[receiver1] + sharePermille[receiver2] + sharePermille[receiver3]);

        update(receiver1);
        update(receiver2);
        update(receiver3);

        sharePermille[receiver1] = share1;
        sharePermille[receiver2] = share2;
        sharePermille[receiver3] = share3;

        ShareChanged(receiver1, share1);
        ShareChanged(receiver2, share2);
        ShareChanged(receiver3, share3);
    }

    /**@dev updates state of receiver at the moment of ether withdraw */
    function update(address receiver) internal {
        // Update unprocessed deposits
        if (lastBalance != this.balance) {
            sumDeposits = deposits(); //first update depoists!
            lastBalance = this.balance; //only then make lastBalanve equal to the current!
        }

        // Claim share of deposits since last claim
        etherBalance[receiver] = etherBalanceOf(receiver);

        // Snapshot deposits summation
        lastSumDeposits[receiver] = sumDeposits;
    }
    
    /**@dev How much ether since last deposit can be claimed  */
    function claimableEther(address receiver) internal constant returns (uint256) {
        return safeSub(deposits(), lastSumDeposits[receiver]) * sharePermille[receiver] / 1000;
    }
}