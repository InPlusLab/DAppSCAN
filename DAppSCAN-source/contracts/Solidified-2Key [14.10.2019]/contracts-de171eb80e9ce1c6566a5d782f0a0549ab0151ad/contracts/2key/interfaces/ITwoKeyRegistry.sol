pragma solidity ^0.4.24;

contract ITwoKeyRegistry {
    function checkIfUserExists(address _userAddress) public view returns (bool);
    function getUserData(address _user) public view returns (bytes32,bytes32,bytes32);
}
