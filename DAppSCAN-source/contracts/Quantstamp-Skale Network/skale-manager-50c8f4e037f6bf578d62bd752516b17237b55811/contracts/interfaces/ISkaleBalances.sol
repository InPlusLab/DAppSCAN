pragma solidity ^0.5.3;

interface ISkaleBalances {
    function withdrawBalance(address to, uint amountOfTokens) external;
}
