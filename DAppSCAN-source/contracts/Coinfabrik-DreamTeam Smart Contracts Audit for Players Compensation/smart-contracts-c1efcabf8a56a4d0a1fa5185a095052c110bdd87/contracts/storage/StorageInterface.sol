pragma solidity ^0.4.18;

interface StorageInterface {

    function transferOwnership (address newOwner) public; // Owners only: revoke access from the calling account and grant access to newOwner
    function grantAccess (address newOwner) public; // Owners only: just grant access to newOwner without revoking the access from the current owner
    function revokeAccess (address previousOwner) public; // Just revoke access from the current owner
    function isOwner (address addr) public view returns(bool);
    function getUint (bytes32 record) public view returns (uint);
    function getString (bytes32 record) public view returns (string);
    function getAddress (bytes32 record) public view returns (address);
    function getBytes (bytes32 record) public view returns (bytes);
    function getBoolean (bytes32 record) public view returns (bool);
    function getInt (bytes32 record) public view returns (int);
    function setString (bytes32 record, string value) public;
    function setUint (bytes32 record, uint value) public;
    function setAddress (bytes32 record, address value) public;
    function setBytes (bytes32 record, bytes value) public;
    function setBoolean (bytes32 record, bool value) public;
    function setInt (bytes32 record, int value) public;

}