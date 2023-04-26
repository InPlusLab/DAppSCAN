pragma solidity ^0.4.10;

import './Vendor.sol';
import './IVendor.sol';
import './IVendorManager.sol';
import '../common/Owned.sol';
import '../common/CheckList.sol';

/**@dev Factory to create and vendors and products */
contract VendorFactory is Owned, Versioned {

    event VendorCreated(address indexed vendorOwner, address indexed vendor, string name, uint256 fee);    

    IVendorManager public manager;    

    function VendorFactory(IVendorManager _manager) public {
        manager = _manager;
        version = 1;
    }

    // allows execution only if this factory is set in manager
    modifier activeOnly {
        require(manager.validFactory(this) && manager.active());
        _;
    }

    /**@dev Creates vendor with specified wallet to receive profit*/
    function createVendor(address vendorWallet, string name)
        public
        activeOnly 
        returns (address)
    {
        Vendor vendor = new Vendor(manager, name, vendorWallet, /*manager.provider(),*/ manager.providerFeePromille());
        vendor.transferOwnership(msg.sender);
        manager.addVendor(msg.sender, vendor);

        VendorCreated(msg.sender, vendor, name, manager.providerFeePromille());
        return vendor;
    }

    /**@dev Creates vendor with given fee, only owner is allowed to call it */
    function createCustomVendor(address vendorOwner, address vendorWallet, string name, uint256 feeInPromille) 
        public
        ownerOnly
        activeOnly        
        returns (address)
    {
        Vendor vendor = new Vendor(manager, name, vendorWallet, /*manager.provider(),*/ feeInPromille);
        vendor.transferOwnership(vendorOwner);
        manager.addVendor(vendorOwner, vendor);

        VendorCreated(vendorOwner, vendor, name, feeInPromille);
        return vendor;
    }
}