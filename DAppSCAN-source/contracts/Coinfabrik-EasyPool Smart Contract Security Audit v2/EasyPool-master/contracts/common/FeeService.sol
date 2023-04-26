pragma solidity ^0.4.24;

import "../abstract/IFeeService.sol";
import "../abstract/IAffiliate.sol";
import "../zeppelin/SafeMath.sol";
import "../zeppelin/Ownable.sol";


/**
 * @title FeeService 
 */
contract FeeService is IFeeService, Ownable {     
    // We could use SafeMath to catch errors in the logic, 
    // but if there are no such errors we can skip it.
    // using SafeMath for uint;  
    
    IAffiliate public affiliate;
    uint public feePerEther;        

    /**
     * @dev Send fee from specified pool creator.
     */
    function sendFee(address poolCreator) external payable {
        require(msg.value > 0);
        require(poolCreator != address(0));
        
        bool success;
        uint affShare;
        uint sharePerEther;

        if(affiliate != address(0)) {
            (sharePerEther, success) = affiliate.getSharePerEther(poolCreator);
            if(success && sharePerEther > 0) {
                require(sharePerEther <= 1 ether);
                affShare = (msg.value * sharePerEther) / 1 ether;
                if(affShare > 0) {
                    affiliate.sendRevenueShare.value(affShare)(poolCreator);
                }            
            }
        }

        emit FeeDistributed(
            poolCreator,
            msg.sender,            
            msg.value,
            affShare
        );
    }

    /**
     * @dev Withdraw contract balance.
     */
    function withdraw() external onlyOwner {
        emit Withdrawal(msg.sender, address(this).balance);
        owner.transfer(address(this).balance);
    }

    /**
     * @dev Set service comission, in terms of 'Fee per Ether'.
     */
    function setFeePerEther(uint newFeePerEther) external onlyOwner {
        emit ServiceFeeChanged(feePerEther, newFeePerEther);
        feePerEther = newFeePerEther;
    }

    /**
     * @dev Attach affiliation service.
     */
    function setAffiliate(address newAffiliate) external onlyOwner {
        emit AffiliateAttached(address(affiliate), newAffiliate);
        affiliate = IAffiliate(newAffiliate);
    }

    /**
     * @dev Get service comission, in terms of 'Fee per Ether'.
     */
    function getFeePerEther() public view returns(uint) {
        return feePerEther;
    }    

    event AffiliateAttached(
        address prevAffiliate, 
        address newAffiliate
    );
    event ServiceFeeChanged(
        uint prevFeePerEther, 
        uint newFeePerEther
    );
    event FeeDistributed(
        address indexed creator,
        address poolAddress,        
        uint totalAmount,
        uint affShare        
    );
    event Withdrawal(
        address destAddress,
        uint amount
    );    
}