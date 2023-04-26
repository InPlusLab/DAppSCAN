pragma solidity ^0.4.10;

/*Interface to ProductEngine library */
library IProductEngine {

    //Purchase information
    struct Purchase {
        uint256 id; //purchase id
        address buyer; //who made a purchase
        string clientId; //product-specific client id
        uint256 price; //unit price at the moment of purchase
        uint256 paidUnits; //how many units
        bool delivered; //true if Product was delivered
        bool badRating; //true if user changed rating to 'bad'
    }

    /**@dev
    Storage data of product
    1. A couple of words on 'denominator'. It shows how many smallest units can 1 unit be splitted into.
    'price' field still represents price per one unit. One unit = 'denominator' * smallest unit. 
    'maxUnits', 'soldUnits' and 'paidUnits' show number of smallest units. 
    For simple products which can't be fractioned 'denominator' should equal 1.

    For example: denominator = 1,000, 'price' = 100,000. 
    a. If user pays for one product (100,000), his 'paidUnits' field will be 1000.
    b. If 'buy' function receives 50,000, that means user is going to buy
        a half of the product, and 'paidUnits' will be calculated as 500.
    c.If 'buy' function receives 100, that means user wants to buy the smallest unit possible
        and 'paidUnits' will be 1;
        
    Therefore 'paidUnits' = 'weiReceived' * 'denominator' / 'price'
    */
    struct ProductData {        
        address owner; //VendorBase - product's owner
        string name; //Name of the product        
        uint256 price; //Price of one product unit        
        uint256 maxUnits; //Max quantity of limited product units, or 0 if unlimited        
        bool isActive; //True if it is possible to buy a product        
        uint256 soldUnits; //How many units already sold        
        uint256 denominator; //This shows how many decimal digits the smallest unit fraction can hold
        mapping (address => uint256) pendingWithdrawals; //List of overpays to withdraw        
        Purchase[] purchases; //Array of purchase information
        mapping (address => uint256) userRating; //index of first-purchase structure in Purchase[] array. Starts with 1 so you need to subtract 1 to get actual!        
    }

    /**@dev 
    Calculates and returns payment details: how many units are bought, 
     what part of ether should be paid and what part should be returned to buyer  */
    function calculatePaymentDetails(IProductEngine.ProductData storage self, uint256 weiAmount, bool acceptLessUnits) 
        public
        constant        
        returns(uint256 unitsToBuy, uint256 etherToPay, uint256 etherToReturn) 
    {
        self; unitsToBuy; etherToPay; etherToReturn; weiAmount; acceptLessUnits;
    } 

    /**@dev 
    Buy product. Send ether with this function in amount equal to desirable product quantity total price
     * clientId - Buyer's product-specific information. 
     * acceptLessUnits - 'true' if buyer doesn't care of buying the exact amount of limited products.
     If N units left and buyer sends payment for N+1 units then settings this flag to 'true' will result in
     buying N units, while 'false' will simply decline transaction 
     * currentPrice - current product price as shown in 'price' property. 
     Used for security reasons to compare actual price with the price at the moment of transaction. 
     If they are not equal, transaction is declined  */
    function buy(IProductEngine.ProductData storage self, string clientId, bool acceptLessUnits, uint256 currentPrice) public;

    /**@dev 
    Call this to return all previous overpays */
    function withdrawOverpay(IProductEngine.ProductData storage self) public;

    /**@dev 
    Marks purchase with given id as delivered or not */
    function markAsDelivered(IProductEngine.ProductData storage self, uint256 purchaseId, bool state) public;

    /**@dev 
    Changes parameters of product */
    function setParams(
        IProductEngine.ProductData storage self,
        string newName, 
        uint256 newPrice,         
        uint256 newMaxUnits,    
        bool newIsActive        
    ) public;

    /**@dev Changes rating of product */
    function changeRating(IProductEngine.ProductData storage self, bool newLikeState) public;
}
