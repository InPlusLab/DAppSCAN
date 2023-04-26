pragma solidity ^0.4.18;

/**@dev Interface of custom PurchaseHandler that performs additional work after payment is made */
contract IPurchaseHandler {
    function handlePurchase(address buyer, uint256 unitsBought, uint256 price) public {}
}
