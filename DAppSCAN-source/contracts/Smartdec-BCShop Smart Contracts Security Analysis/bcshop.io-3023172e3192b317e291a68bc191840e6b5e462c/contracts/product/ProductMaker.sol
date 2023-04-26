pragma solidity ^0.4.18;

import "../common/Active.sol";
import "../common/Manageable.sol";
import "./ProductStorage.sol";

contract ProductMaker is Active {

    //
    // Events
    event ProductCreated
    (
        address indexed owner, 
        uint256 price, 
        uint256 maxUnits,
        uint256 startTime, 
        uint256 endTime, 
        bool useEscrow,
        string name,
        string data
    );

    event ProductEdited
    (
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

    //
    // Storage data
    IProductStorage public productStorage;    


    //
    // Methods

    function ProductMaker(IProductStorage _productStorage) public {
        productStorage = _productStorage;
    }

    /**@dev Creates product. Can be called by end user */
    function createSimpleProduct(
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
        activeOnly
    {
        if(startTime > 0 && endTime > 0) {
            require(endTime > startTime);
        }

        productStorage.createProduct(msg.sender, price, maxUnits, isActive, startTime, endTime, useEscrow, useFiatPrice, name, data);
        //ProductCreated(msg.sender, price, maxUnits, startTime, endTime, 0, name, data);
    }

    /**@dev Creates product and enters the information about vendor wallet. Can be called by end user */
    function createSimpleProductAndVendor(
        address wallet,
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
        activeOnly
    {
        productStorage.setVendorInfo(msg.sender, wallet, productStorage.getVendorFee(msg.sender));   
        createSimpleProduct(price, maxUnits, isActive, startTime, endTime, useEscrow, useFiatPrice, name, data);
        //productStorage.createProduct(msg.sender, price, maxUnits, isActive, startTime, endTime, useEscrow, useFiatPrice, name, data);
        //ProductCreated(msg.sender, price, maxUnits, startTime, endTime, 0, name, data);
    }

    /**@dev Edits product in the storage */   
    function editSimpleProduct(
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
        activeOnly
    {
        require(msg.sender == productStorage.getProductOwner(productId));                
        if(startTime > 0 && endTime > 0) {
            require(endTime > startTime);
        }

        //uint256[5] memory inputs = [productId, price, maxUnits, startTime, endTime];
        //productStorage.editProduct(inputs[0], inputs[1], inputs[2], isActive, inputs[3], inputs[4], useEscrow, useFiatPrice, name, data);        
        
        productStorage.editProduct(productId, price, maxUnits, isActive, startTime, endTime, useEscrow, useFiatPrice, name, data);        
        ProductEdited(productId, price, useFiatPrice, maxUnits, isActive, startTime, endTime, useEscrow, name, data);
        // productStorage.editProductData(productId, price, useFiatPrice, maxUnits, isActive, startTime, endTime, useEscrow);        
        // productStorage.editProductText(productId, name, data);        
    }

    /**@dev Changes vendor wallet for profit */
    function setVendorWallet(address wallet) public 
    activeOnly 
    {
        productStorage.setVendorInfo(msg.sender, wallet, productStorage.getVendorFee(msg.sender));
    }
}