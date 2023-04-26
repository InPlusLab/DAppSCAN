pragma solidity ^0.4.10;

contract AddressStorage {

    address public address1;
    address public address2;
    address public address3;
    address public address4;

    //function AddressStorage() {}

    function AddressStorage(address a1, address a2, address a3, address a4) {
        address1 = a1;
        address2 = a2;
        address3 = a3;
        address4 = a4;
    }

    function setAddresses(address a1, address a2, address a3, address a4) {
        address1 = a1;
        address2 = a2;
        address3 = a3;
        address4 = a4;
    }
}