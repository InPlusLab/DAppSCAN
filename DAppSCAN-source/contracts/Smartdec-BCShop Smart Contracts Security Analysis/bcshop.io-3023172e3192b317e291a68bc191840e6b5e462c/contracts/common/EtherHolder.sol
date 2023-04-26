pragma solidity ^0.4.18;

import "../common/Owned.sol";

/**@dev Contract that can hold and receive Ether and transfer it to anybody */
contract EtherHolder is Owned {
    
    //
    // Methods

    function EtherHolder() public {
    } 

    /**@dev withdraws amount of ether to specific adddress */
    function withdrawEtherTo(uint256 amount, address to) public ownerOnly {
        to.transfer(amount);
    }

    function() payable {}
}