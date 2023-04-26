pragma solidity 0.6.12;

interface CERC20 {
  function comptroller() external view returns (address);
  function exchangeRateStored() external view returns (uint256);
}
