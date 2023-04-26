pragma solidity ^0.4.18;

import "../common/SafeMathLib.sol";
import "../common/Manageable.sol";
import "./IProductStorage.sol";

/**@dev Contract that stores all products' data. Contains simple methods for retrieving and changing products */
contract ProductStorage is Manageable, IProductStorage {
    
    using SafeMathLib for uint256;

    //
    //Inner types

    //Escrow information
    struct EscrowData {
        address customer;   //customer address
        uint256 fee;        //fee to provider
        uint256 profit;     //profit to vendor
        uint256 timestamp;  //date and time of purchase
    }

    //Purchase information
    struct Purchase {
        PurchaseState state;
    }

    /**@dev
    Storage data of product */
    struct ProductData {    
        //product's creator
        address owner;        
        //price of one product unit in WEI
        uint256 price;
        //max quantity of limited product units, or 0 if unlimited
        uint256 maxUnits;
        //true if it is possible to buy a product
        bool isActive;
        //how many units already sold
        uint256 soldUnits;
        //timestamp of the purchases start
        uint256 startTime;
        //timestamp of the purchases end
        uint256 endTime;
        //true if escrow should be used
        bool useEscrow;
        //true if fiat price is used, in that case 
        bool useFiatPrice;
        //name of the product 
        string name; 
        //custom fields
        string data;
        //array of purchase information
        Purchase[] purchases;
    }    

    /**@dev Vendor-related information  */
    struct VendorInfo {
        address wallet;      //wallet to get profit        
        uint16 feePermille;   //fee permille for that vendor or 0 if default fee is used
    }
    


    //
    //Events
    event ProductAdded(
        uint256 indexed id,
        address indexed owner,         
        uint256 price, 
        uint256 maxUnits,
        bool isActive,         
        uint256 startTime, 
        uint256 endTime, 
        bool useEscrow,
        bool useFiatPrice,
        string name,
        string data
    );

    event PurchaseAdded(
        uint256 indexed productId,
        uint256 indexed id,
        address indexed buyer,    
        uint256 price,         
        uint256 paidUnits,        
        string clientId  
    );

    event ProductEdited(
        uint256 indexed productId,        
        uint256 price, 
        bool useFiatPrice,
        uint256 maxUnits, 
        bool isActive,
        uint256 startTime, 
        uint256 endTime,
        bool useEscrow,        
        string name,
        string data
    );

    event CustomParamsSet(uint256 indexed productId, address feePolicy);

    event VendorInfoSet(address indexed vendor, address wallet, uint16 feePermille);

    event EscrowDataSet(
        uint256 indexed productId,
        uint256 indexed purchaseId,   
        address indexed customer,         
        uint256 fee, 
        uint256 profit, 
        uint256 timestamp
    );



    //
    //Storage data    

    //List of all created products
    ProductData[] public products;
    //true if [x] product is not allowed to be purchase
    mapping(uint256=>bool) public banned;
    //vendor-related information of specific wallet
    mapping(address=>VendorInfo) public vendors;
    //first index is product id, second one - purchase id
    mapping(uint256=>mapping(uint256=>EscrowData)) public escrowData;


    //
    //Modifiers
    modifier validProductId(uint256 productId) {
        require(productId < products.length);
        _;
    }

    
    
    //
    //Methods

    function ProductStorage() public {        
    }

    /**@dev Returns total amount of products */
    function getTotalProducts() public constant returns(uint256) {
        return products.length;
    }

    /**@dev Returns text information about product */
    function getTextData(uint256 productId) 
        public
        constant
        returns(            
            string name, 
            string data
        ) 
    {
        ProductData storage p = products[productId];
        return (            
            p.name, 
            p.data
        );
    }

    /**@dev Returns information about product */
    function getProductData(uint256 productId) 
        public
        constant
        returns(            
            uint256 price, 
            uint256 maxUnits, 
            uint256 soldUnits
        ) 
    {
        ProductData storage p = products[productId];
        return (            
            p.price, 
            p.maxUnits, 
            p.soldUnits
        );
    }

    /**@dev Returns information about product's active state and time limits */
    function getProductActivityData(uint256 productId) 
        public
        constant
        returns(            
            bool active, 
            uint256 startTime, 
            uint256 endTime
        ) 
    {
        ProductData storage p = products[productId];
        return (            
            p.isActive, 
            p.startTime, 
            p.endTime
        );
    }

    /**@dev Returns product's creator */
    function getProductOwner(uint256 productId) 
        public 
        constant         
        returns(address)
    {
        return products[productId].owner;
    }   

    /**@dev Returns product's price */
    function getProductPrice(uint256 productId) 
        public 
        constant         
        returns(uint256)
    {
        return products[productId].price;
    }   

    /**@dev Returns product's escrow usage */
    function isEscrowUsed(uint256 productId) 
        public 
        constant         
        returns(bool)
    {
        return products[productId].useEscrow;
    }

    /**@dev Returns true if product price is set in fiat currency */
    function isFiatPriceUsed(uint256 productId) 
        public 
        constant         
        returns(bool)
    {
        return products[productId].useFiatPrice;
    }   

    /**@dev Returns true if product can be bought now */
    function isProductActive(uint256 productId) 
        public 
        constant         
        returns(bool)
    {
        return products[productId].isActive && 
            (products[productId].startTime == 0 || now >= products[productId].startTime) &&
            (products[productId].endTime == 0 || now <= products[productId].endTime);
    }   

    /**@dev Returns total amount of purchase transactions for the given product */
    function getTotalPurchases(uint256 productId) 
        public 
        constant
        returns (uint256) 
    {
        return products[productId].purchases.length;
    }

    /**@dev Returns information about purchase with given index for the given product */
    function getPurchase(uint256 productId, uint256 purchaseId) 
        public
        constant         
        returns(PurchaseState state) 
    {
        Purchase storage p = products[productId].purchases[purchaseId];
        return p.state;
    }

    /**@dev Returns escrow-related data for specified purchase */
    function getEscrowData(uint256 productId, uint256 purchaseId)
        public
        constant
        returns (address, uint256, uint256, uint256)
    {
        EscrowData storage data = escrowData[productId][purchaseId];
        return (data.customer, data.fee, data.profit, data.timestamp);
    }

    /**@dev Returns wallet for specific vendor */
    function getVendorWallet(address vendor) public constant returns(address) {
        return vendors[vendor].wallet == 0 ? vendor : vendors[vendor].wallet;
    }

    /**@dev Returns fee permille for specific vendor */
    function getVendorFee(address vendor) public constant returns(uint16) {
        return vendors[vendor].feePermille;
    }

    function setVendorInfo(address vendor, address wallet, uint16 feePermille) 
        public 
        managerOnly 
    {
        vendors[vendor].wallet = wallet;
        vendors[vendor].feePermille = feePermille;
        VendorInfoSet(vendor, wallet, feePermille);
    }

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
    ) 
        public 
        managerOnly
    {
        ProductData storage product = products[products.length++];
        product.owner = owner;
        product.price = price;
        product.maxUnits = maxUnits;
        product.isActive = isActive;
        product.startTime = startTime;
        product.endTime = endTime;
        product.isActive = isActive;
        product.useEscrow = useEscrow;
        product.useFiatPrice = useFiatPrice;
        product.name = name;
        product.data = data;
        ProductAdded(products.length - 1, owner, price, maxUnits, isActive, startTime, endTime, useEscrow, useFiatPrice, name, data);
    }


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
    ) 
        public 
        validProductId(productId)
        managerOnly
    {
        ProductData storage product = products[productId];
        product.price = price;
        product.maxUnits = maxUnits;
        product.startTime = startTime;
        product.endTime = endTime;
        product.isActive = isActive;
        product.useEscrow = useEscrow;
        product.useFiatPrice = useFiatPrice;
        product.name = name;
        product.data = data;
        ProductEdited(productId, price,useFiatPrice, maxUnits, isActive, startTime, endTime, useEscrow, name, data);
    }

    // function editProductData(
    //     uint256 productId,        
    //     uint256 price, 
    //     bool useFiatPrice,
    //     uint256 maxUnits, 
    //     bool isActive,
    //     uint256 startTime, 
    //     uint256 endTime,
    //     bool useEscrow
    // ) 
    //     public 
    //     validProductId(productId)
    //     managerOnly
    // {
    //     // ProductData storage product = products[productId];
    //     // product.price = price;
    //     // product.maxUnits = maxUnits;
    //     // product.startTime = startTime;
    //     // product.endTime = endTime;
    //     // product.isActive = isActive;
    //     // product.useEscrow = useEscrow;
    //     // product.useFiatPrice = useFiatPrice;
    //     ProductEdited(productId, price, useFiatPrice, maxUnits, isActive, startTime, endTime, useEscrow, "", "");
    // }

    // function editProductText(
    //     uint256 productId,        
    //     string name,
    //     string data
    // ) 
    //     public 
    //     validProductId(productId)
    //     managerOnly
    // {
    //     // ProductData storage product = products[productId];
    //     // product.name = name;
    //     // product.data = data;
    //     ProductEdited(productId, 0, false, 0, false, 0, 0, false, name, data);
    // }


    /**@dev Changes the value of currently sold units */
    function changeSoldUnits(uint256 productId, uint256 soldUnits)
        public 
        validProductId(productId)
        managerOnly
    {
        products[productId].soldUnits = soldUnits;
    }

    /**@dev Changes owner of the product */
    function changeOwner(uint256 productId, address newOwner) 
        public 
        validProductId(productId)
        managerOnly
    {
        products[productId].owner = newOwner;
    }

    /**@dev Marks product as banned. other contracts shoudl take this into account when interacting with product */
    function banProduct(uint256 productId, bool state) 
        public 
        managerOnly
        validProductId(productId)
    {
        banned[productId] = state;
    }

    /**@dev  Adds new purchase to the list of given product */
    function addPurchase(
        uint256 productId,        
        address buyer,    
        uint256 price,         
        uint256 paidUnits,        
        string clientId   
    ) 
        public 
        managerOnly
        validProductId(productId)
        returns (uint256)
    {
        PurchaseAdded(product.purchases.length, productId, buyer, price, paidUnits, clientId);        
        
        ProductData storage product = products[productId];
        product.soldUnits = product.soldUnits.safeAdd(paidUnits);

        //Purchase storage purchase = product.purchases[product.purchases.length++];
        product.purchases.length++;
        //purchase.state = state;
        return product.purchases.length - 1;
    }

    /**@dev Changes purchase state of specific purchase */
    function changePurchase(uint256 productId, uint256 purchaseId, PurchaseState state) 
        public 
        managerOnly 
        validProductId(productId)
    {
        require(purchaseId < products[productId].purchases.length);

        products[productId].purchases[purchaseId].state = state;
    }    

    /**@dev Sets escrow data for specified purchase */
    function setEscrowData(uint256 productId, uint256 purchaseId, address customer, uint256 fee, uint256 profit, uint256 timestamp) 
        public
        managerOnly
        validProductId(productId)
    {
        require(products[productId].useEscrow);
        require(purchaseId < products[productId].purchases.length);

        EscrowData storage data = escrowData[productId][purchaseId];
        data.customer = customer;
        data.fee = fee;
        data.profit = profit;
        data.timestamp = timestamp;

        EscrowDataSet(productId, purchaseId, customer, fee, profit, timestamp);
    }
}