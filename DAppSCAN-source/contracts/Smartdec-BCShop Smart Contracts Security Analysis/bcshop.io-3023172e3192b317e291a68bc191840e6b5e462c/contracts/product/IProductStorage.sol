pragma solidity ^0.4.18;

//Abstraction of ProductStorage
contract IProductStorage {

    //
    //Inner types
    /**dev Purchase state 
        0-finished. purchase is completed and can't be reverted, 
        1-paid. can be complained using escrow.
        2-complain. there was a complain
        3-canceled. customer won the dispute and got eth back
        4-pending. vendor can withdraw his funds from escrow
    */
    enum PurchaseState {Finished, Paid, Complain, Canceled, Pending}

    //
    // Methods

    function banned(uint256 productId) public constant returns(bool) {}

    function getTotalProducts() public constant returns(uint256);    

    function getTextData(uint256 productId) public constant returns(string name, string data);    

    /**@dev Returns information about purchase with given index for the given product */
    function getProductData(uint256 productId) public constant returns(
            uint256 price, 
            uint256 maxUnits, 
            uint256 soldUnits
        );    

    function getProductActivityData(uint256 productId) public constant returns(
            bool active,
            uint256 startTime,
            uint256 endTime
        );

    /**@dev Returns product's creator */
    function getProductOwner(uint256 productId) public constant returns(address);    

    /**@dev Returns product's price in wei */
    function getProductPrice(uint256 productId) public constant returns(uint256);    

    function isEscrowUsed(uint256 productId) public constant returns(bool);

    function isFiatPriceUsed(uint256 productId) public constant returns(bool);

    function isProductActive(uint256 productId) public constant returns(bool);

    /**@dev Returns total amount of purchase transactions for the given product */
    function getTotalPurchases(uint256 productId) public constant returns (uint256);    

    /**@dev Returns information about purchase with given index for the given product */
    function getPurchase(uint256 productId, uint256 purchaseId) public constant returns(PurchaseState);    

    /**@dev Returns escrow-related data for specified purchase */
    function getEscrowData(uint256 productId, uint256 purchaseId)
        public
        constant
        returns (address, uint256, uint256, uint256);    

    /**@dev Returns wallet for specific vendor */
    function getVendorWallet(address vendor) public constant returns(address);    

    /**@dev Returns fee permille for specific vendor */
    function getVendorFee(address vendor) public constant returns(uint16);    

    function setVendorInfo(address vendor, address wallet, uint16 feePermille) public;        

    /**@dev Adds new product to the storage */
    function createProduct(
        address owner,         
        uint256 price, 
        uint256 maxUnits,
        bool isActive,
        uint256 startTime, 
        uint256 endTime,
        bool useEscrow,
        bool useFiatPrice,
        string name,
        string data
    ) public;

    /**@dev Edits product in the storage */   
    function editProduct(
        uint256 productId,        
        uint256 price, 
        uint256 maxUnits, 
        bool isActive,
        uint256 startTime, 
        uint256 endTime,
        bool useEscrow,
        bool useFiatPrice,
        string name,
        string data
    ) public;

    // function editProductData(
    //     uint256 productId,        
    //     uint256 price,
    //     bool useFiatPrice, 
    //     uint256 maxUnits, 
    //     bool isActive,
    //     uint256 startTime, 
    //     uint256 endTime,
    //     bool useEscrow        
    // ) public;

    // function editProductText(
    //     uint256 productId,        
    //     string name,
    //     string data
    // ) public;

    /**@dev Changes the value of sold units */
    function changeSoldUnits(uint256 productId, uint256 soldUnits) public;
    
    /**@dev  Adds new purchase to the list of given product */
    function addPurchase(
        uint256 productId,        
        address buyer,    
        uint256 price,         
        uint256 paidUnits,
        string clientId   
    ) public returns (uint256);    

    /**@dev Changes purchase state */
    function changePurchase(uint256 productId, uint256 purchaseId, PurchaseState state) public;

    /**@dev Sets escrow data for specified purchase */
    function setEscrowData(
        uint256 productId, 
        uint256 purchaseId, 
        address customer, 
        uint256 fee, 
        uint256 profit, 
        uint256 timestamp
    ) public;
}