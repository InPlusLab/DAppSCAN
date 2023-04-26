pragma solidity ^0.4.10;

import "../common/IOwned.sol";

/**@dev Vendor interface for interaction with manager contracts */
contract IVendor is IOwned {
    /**@dev Returns count of products */
    //function getProductsCount() public constant returns(uint32) {}

    /**@dev Adds product to storage */
    function addProduct(address product) public;    
}