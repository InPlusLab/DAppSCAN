pragma solidity ^0.4.18;

contract IEtherPriceProvider {
    function rate() public constant returns (uint256);
}