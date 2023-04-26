pragma solidity ^0.4.10;

import './Vendor.sol';

contract NamedVendor is Vendor {

    string public name;

    function NamedVendor(
        string vendorName, 
        address vendorWallet, 
        address serviceProvider, 
        uint256 feeInPromille) 
        Vendor(vendorWallet, serviceProvider, feeInPromille)
    {
        name = vendorName;
    }

    /**@dev Sets new name */
    function setName(string newName) ownerOnly {
        name = newName;
    }

}