pragma solidity ^0.4.18;

import "./StorageInterface.sol";
import "./BasicStorage.sol";

contract DreamTeamStorage is BasicStorage {

    mapping(bytes32 => uint) uintStorage;
    mapping(bytes32 => string) stringStorage;
    mapping(bytes32 => address) addressStorage;
    mapping(bytes32 => bytes) bytesStorage;
    mapping(bytes32 => bool) booleanStorage;
    mapping(bytes32 => int) intStorage;

    function DreamTeamStorage (address[] initialOwners) BasicStorage(initialOwners) public {}

    function getUint (bytes32 record) public view returns (uint) { return uintStorage[record]; }
    function getString (bytes32 record) public view returns (string) { return stringStorage[record]; }
    function getAddress (bytes32 record) public view returns (address) { return addressStorage[record]; }
    function getBytes (bytes32 record) public view returns (bytes) { return bytesStorage[record]; }
    function getBoolean (bytes32 record) public view returns (bool) { return booleanStorage[record]; }
    function getInt (bytes32 record) public view returns (int) { return intStorage[record]; }
    function setString (bytes32 record, string value) public ownersOnly { stringStorage[record] = value; }
    function setUint (bytes32 record, uint value) public ownersOnly { uintStorage[record] = value; }
    function setAddress (bytes32 record, address value) public ownersOnly { addressStorage[record] = value; }
    function setBytes (bytes32 record, bytes value) public ownersOnly { bytesStorage[record] = value; }
    function setBoolean (bytes32 record, bool value) public ownersOnly { booleanStorage[record] = value; }
    function setInt (bytes32 record, int value) public ownersOnly { intStorage[record] = value; }

}