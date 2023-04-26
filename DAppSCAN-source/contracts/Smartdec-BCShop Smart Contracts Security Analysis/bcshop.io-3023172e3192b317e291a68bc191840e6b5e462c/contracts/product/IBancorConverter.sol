pragma solidity ^0.4.18;

contract IBancorConverter {
    function convertFor(address[] _path, uint256 _amount, uint256 _minReturn, address _for)
        public
        payable
        returns (uint256);
}