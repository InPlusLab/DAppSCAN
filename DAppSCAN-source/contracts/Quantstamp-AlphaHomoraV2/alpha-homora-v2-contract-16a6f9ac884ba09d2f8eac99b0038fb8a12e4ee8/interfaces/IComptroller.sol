pragma solidity 0.6.12;

interface IComptroller {
  function enterMarkets(address[] memory cTokens) external returns (uint[] memory);
}
