pragma solidity ^0.5.10;

contract SolidityAccountUtils {
    function transferTo(address payable _to) public payable {
        _to.transfer(msg.value);
    }

    function getBalance(address _address) public view returns (uint256) {
        return _address.balance;
    }
}