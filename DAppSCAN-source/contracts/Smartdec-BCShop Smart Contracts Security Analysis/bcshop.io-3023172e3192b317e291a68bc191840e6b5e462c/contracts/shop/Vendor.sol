pragma solidity ^0.4.10;

import './Product.sol';
import './VendorBase.sol';
import './IVendor.sol';
import './IVendorManager.sol';
import "../common/Versioned.sol";

///Vendor-provider agreement with the ability to create products
contract Vendor is VendorBase, Versioned, IVendor {

    event ProductCreated(address indexed product);
    event Created(string name, uint32 version, uint256 fee, address vendorWallet); 
    //event FeeChanged(uint256 fee);
    event ParametersChanged(address wallet, string name);

    /**@dev List of all created products
    We can save around 50k gas on creation of vendor and product by deleting this array and using 'dumb contracts' instead */
    address[] public products;

    /**Vendor's name */    
    string public name;
    
    //allows execution only from manager's factory contract
    modifier factoryOnly() {        
        require(vendorManager.validFactory(msg.sender));
        _;
    }

    function Vendor(
        IVendorManager manager, 
        string vendorName, 
        address vendorWallet, 
        // address serviceProvider, 
        uint256 feeInPromille
    ) 
        public
    {
        require(address(manager) != 0x0);
        require(vendorWallet != 0x0);
        //require(serviceProvider != 0x0);
        require(feeInPromille <= 1000);

        name = vendorName;
        vendorManager = manager;
        vendor = vendorWallet;
        //provider = serviceProvider;
        providerFeePromille = feeInPromille;
        
        version = 1;
        Created(vendorName, version, feeInPromille, vendorWallet);
    } 

    /**@dev IVendor override. Returns count of products */
    function getProductsCount() public constant returns (uint32) {
       return uint32(products.length);
    }

    function setParams(address newWallet, string newName) public ownerOnly {
        vendor = newWallet;
        name = newName;
        ParametersChanged(vendor, name);
    } 

    /**@dev IVendor override. Adds product to storage */
    function addProduct(address product) public factoryOnly {
        products.push(product);
        ProductCreated(product);
    }

    /**@dev Sets new fee, only owner of vendor manager should call it */
    // function setFee(uint256 newFeePromille) {
    //     require(msg.sender == vendorManager.owner());
    //     providerFeePromille = newFeePromille;
    //     FeeChanged(providerFeePromille);
    // }
}