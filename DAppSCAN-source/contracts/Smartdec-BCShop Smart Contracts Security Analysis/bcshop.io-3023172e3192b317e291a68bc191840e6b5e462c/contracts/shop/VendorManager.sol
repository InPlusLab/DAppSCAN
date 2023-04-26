pragma solidity ^0.4.10;

import "../common/Owned.sol";
import "../common/Versioned.sol";
import "./IVendorManager.sol";

/**@dev 
The main manager for platform. Stores vendor's addresses. 
Contains refrence to factory contract that creates Vendors and Products */
contract VendorManager is IVendorManager, Owned, Versioned {

    event VendorAdded(address indexed vendorOwner, address indexed vendor);    
        
    mapping(address => bool) public validVendor; //true if address was created by factory
    mapping(address => address[]) public vendorLists;   //List of vendors grouped by ots owner    
    mapping(address => bool) public validFactory;   //true if it is valid factory for creation
    address public provider;                        //provider wallet to receive fee
    uint16 public providerFeePromille;             //fee promille [0-1000]
    bool public active;                             //true if can perform operations

    //allows execution only from factory contract
    modifier factoryOnly() {        
        require(validFactory[msg.sender]);
        _;
    }

    function VendorManager(address serviceProvider, uint16 feePromille) public {
        require(feePromille <= 1000);
        
        provider = serviceProvider;        
        providerFeePromille = feePromille;

        active = true;
        version = 1;
    }    

    /**@dev Returns a number of vendor contracts created by specific owner */
    function getVendorCount(address vendorOwner) public constant returns (uint256) {
        return vendorLists[vendorOwner].length;
    }

    /**@dev Adds vendor to storage */
    function addVendor(address vendorOwner, address vendor) public factoryOnly {
        vendorLists[vendorOwner].push(vendor);
        validVendor[vendor] = true;    
        VendorAdded(vendorOwner, vendor);
    }

    /**@dev sets new vendor/product factory */
    function setFactory(address newFactory, bool state) public ownerOnly {
        //factory = newFactory;
        validFactory[newFactory] = state;
    }

    /**@dev Changes default provider settings */
    function setParams(address newProvider, uint16 newFeePromille) public ownerOnly {
        require(newFeePromille <= 1000);

        provider = newProvider;
        providerFeePromille = newFeePromille;
    }

    /**@dev Changes 'active' state */
    function setActive(bool state) public ownerOnly {
        active = state;
    }

    /**@dev Changes valid vendor state */
    function setValidVendor(address vendor, bool state) ownerOnly {
        validVendor[vendor] = state;
    }
}