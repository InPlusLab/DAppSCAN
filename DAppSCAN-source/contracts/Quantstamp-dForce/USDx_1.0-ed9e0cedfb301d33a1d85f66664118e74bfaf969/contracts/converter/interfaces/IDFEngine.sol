pragma solidity ^0.5.2;

contract IDFEngine {
    function deposit(address _sender, address _tokenID, uint _feeTokenIdx, uint _amount) public returns (uint);
    function withdraw(address _sender, address _tokenID, uint _feeTokenIdx, uint _amount) public returns (uint);
    function destroy(address _sender, uint _feeTokenIdx, uint _amount) public returns (bool);
    function claim(address _sender, uint _feeTokenIdx) public returns (uint);
    function oneClickMinting(address _sender, uint _feeTokenIdx, uint _amount) public;
}
