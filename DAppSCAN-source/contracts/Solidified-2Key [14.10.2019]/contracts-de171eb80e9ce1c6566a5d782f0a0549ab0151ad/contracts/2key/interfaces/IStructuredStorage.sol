pragma solidity ^0.4.0;

contract IStructuredStorage {

    function setProxyLogicContractAndDeployer(address _proxyLogicContract, address _deployer) external;
    function setProxyLogicContract(address _proxyLogicContract) external;

    // *** Getter Methods ***
    function getUint(bytes32 _key) external view returns(uint);
    function getString(bytes32 _key) external view returns(string);
    function getAddress(bytes32 _key) external view returns(address);
    function getBytes(bytes32 _key) external view returns(bytes);
    function getBool(bytes32 _key) external view returns(bool);
    function getInt(bytes32 _key) external view returns(int);
    function getBytes32(bytes32 _key) external view returns(bytes32);

    // *** Getter Methods For Arrays ***
    function getBytes32Array(bytes32 _key) external view returns (bytes32[]);
    function getAddressArray(bytes32 _key) external view returns (address[]);
    function getUintArray(bytes32 _key) external view returns (uint[]);
    function getIntArray(bytes32 _key) external view returns (int[]);
    function getBoolArray(bytes32 _key) external view returns (bool[]);

    // *** Setter Methods ***
    function setUint(bytes32 _key, uint _value) external;
    function setString(bytes32 _key, string _value) external;
    function setAddress(bytes32 _key, address _value) external;
    function setBytes(bytes32 _key, bytes _value) external;
    function setBool(bytes32 _key, bool _value) external;
    function setInt(bytes32 _key, int _value) external;
    function setBytes32(bytes32 _key, bytes32 _value) external;

    // *** Setter Methods For Arrays ***
    function setBytes32Array(bytes32 _key, bytes32[] _value) external;
    function setAddressArray(bytes32 _key, address[] _value) external;
    function setUintArray(bytes32 _key, uint[] _value) external;
    function setIntArray(bytes32 _key, int[] _value) external;
    function setBoolArray(bytes32 _key, bool[] _value) external;

    // *** Delete Methods ***
    function deleteUint(bytes32 _key) external;
    function deleteString(bytes32 _key) external;
    function deleteAddress(bytes32 _key) external;
    function deleteBytes(bytes32 _key) external;
    function deleteBool(bytes32 _key) external;
    function deleteInt(bytes32 _key) external;
    function deleteBytes32(bytes32 _key) external;
}
