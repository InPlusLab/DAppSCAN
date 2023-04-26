pragma solidity ^0.4.10;

/**@dev Pricing policy of contract that sells things. Not used yet */
contract IPricingPolicy {

    /**@dev Calculates amount of products that can be bought and also a remainder(change) */
    function getTotalProducts(uint256 price, uint256 amountPaid) constant returns(uint256 units, uint256 change);

}