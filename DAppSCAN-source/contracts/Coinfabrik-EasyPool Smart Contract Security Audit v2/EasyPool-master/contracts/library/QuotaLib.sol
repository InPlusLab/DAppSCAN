pragma solidity ^0.4.24;

import "../zeppelin/SafeMath.sol";


/**
 * @title QuotaLib 
 */
library QuotaLib {    
    using SafeMath for uint;

    /**     
     * @dev Quota storage structure. Holds information about 
     * total amount claimed and claimed shares per address.
     */
    struct Storage {
        mapping (address => uint) claimedShares;
        uint claimedAmount;
    }

    /**     
     * @dev Calculate and claim share.
     */
    function claimShare(Storage storage self, address addr, uint currentAmount, uint[2] fraction) internal returns (uint) {
        uint share = calcShare(self, addr, currentAmount, fraction);
        self.claimedShares[addr] = self.claimedShares[addr].add(share);
        self.claimedAmount = self.claimedAmount.add(share);
        return share;
    }

    /**     
     * @dev Calculate share.
     */
    function calcShare(Storage storage self, address addr, uint currentAmount, uint[2] fraction) internal view returns (uint) {
        uint totalShare = share(currentAmount.add(self.claimedAmount), fraction);
        uint claimedShare = self.claimedShares[addr];        
        assert(totalShare >= claimedShare);
        if(totalShare == claimedShare) {
            return 0;
        }        
        return totalShare - claimedShare;
    }    

    /**     
     * @dev Undo claim.
     */
    function undoClaimShare(Storage storage self, address addr, uint amount) internal {
        assert(self.claimedShares[addr] >= amount);
        self.claimedShares[addr] -= amount;
        self.claimedAmount -= amount;
    }

    /**     
     * @dev ...
     */
    function share(uint amount, uint[2] fraction) private pure returns (uint) {
        return amount.mul(fraction[0]).div(fraction[1]);
    }
}