pragma solidity >=0.8.0;

interface ISingleBond {
  function getEpoches() external view returns(address[] memory);
  function getEpoch(uint256 id) external view returns(address);
  function redeem(address[] memory epochs, uint[] memory amounts, address to) external;
  function redeemOrTransfer(address[] memory epochs, uint[] memory amounts, address to) external;
  function multiTransfer(address[] memory epochs, uint[] memory amounts, address to) external;
}