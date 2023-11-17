pragma solidity ^0.4.23;

interface StorageInterface {

    function transferOwnership (address newOwner) external; // Owners only: revoke access from the calling account and grant access to newOwner
    function grantAccess (address newOwner) external; // Owners only: just grant access to newOwner without revoking the access from the current owner
    function revokeAccess (address previousOwner) external; // Just revoke access from the current owner
    function isOwner (address addr) external view returns(bool);
    function getUint (bytes32 record) external view returns (uint);
    function getString (bytes32 record) external view returns (string);
    function getAddress (bytes32 record) external view returns (address);
    function getBytes (bytes32 record) external view returns (bytes);
    function getBoolean (bytes32 record) external view returns (bool);
    function getInt (bytes32 record) external view returns (int);
    function setString (bytes32 record, string value) external;
    function setUint (bytes32 record, uint value) external;
    function setAddress (bytes32 record, address value) external;
    function setBytes (bytes32 record, bytes value) external;
    function setBoolean (bytes32 record, bool value) external;
    function setInt (bytes32 record, int value) external;

}