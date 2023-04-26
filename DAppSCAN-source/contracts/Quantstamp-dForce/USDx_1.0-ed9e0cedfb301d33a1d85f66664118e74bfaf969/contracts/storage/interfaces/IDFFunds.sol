pragma solidity ^0.5.2;

contract IDFFunds {
    function transferOut(address _tokenID, address _to, uint _amount) public returns (bool);
}