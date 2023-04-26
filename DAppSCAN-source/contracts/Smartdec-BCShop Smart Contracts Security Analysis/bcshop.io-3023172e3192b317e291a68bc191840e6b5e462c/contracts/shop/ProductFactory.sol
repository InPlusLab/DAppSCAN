pragma solidity ^0.4.18;

import './IProduct.sol';
import './Product.sol';
import './IVendor.sol';
import './IVendorManager.sol';
import '../common/Owned.sol';
import '../common/CheckList.sol';

/**@dev Factory to create and vendors and products */
contract ProductFactory is Owned, Versioned {
    
    event ProductCreated(address indexed product, address indexed vendor, string name);
    event ProductAdded(address indexed product, address indexed vendor);

    IVendorManager public manager;
    ICheckList public allowedProducts;

    function ProductFactory(IVendorManager _manager, ICheckList _allowedProducts) public {
        manager = _manager;
        allowedProducts = _allowedProducts;
        version = 1;
    }

    // allows execution only if this factory is set in manager
    modifier activeOnly {
        require(manager.validFactory(this) && manager.active());
        _;
    }

    /**@dev Creates product with specified parameters */
    function createProduct(
        IVendor vendor,
        string name, 
        uint256 unitPriceInWei,
        uint256 maxQuantity,
        uint256 denominator
    )
        public      
        activeOnly 
        returns (address) 
    {
        //check that sender is owner of given vendor
        require(msg.sender == vendor.owner());

        //check that vendor is stored in manager
        require(manager.validVendor(vendor));        

        Product product = new Product(            
            name, 
            unitPriceInWei, 
            maxQuantity,
            denominator);            

        product.transferOwnership(address(vendor));
        vendor.addProduct(address(product));
        allowedProducts.set(product, true);

        ProductCreated(product, vendor, name);        
        return product;
    }

    /**@dev Manually adds externally created product to a vendor. 
    In addition to calling this method product ownership should be transfered to vendor*/
    function addProduct(IVendor vendor, IProduct product) 
        public
        activeOnly
        ownerOnly
    {
        vendor.addProduct(address(product));
        allowedProducts.set(product, true);
        ProductAdded(product, vendor);  
    }
}