//SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;


interface IDYToken {
  function deposit(uint _amount, address _toVault) external;
  function depositTo(address _to, uint _amount, address _toVault) external;
  function depositCoin(address to, address _toVault) external payable;

  function withdraw(address _to, uint _shares, bool needWETH) external;
  function underlyingTotal() external view returns (uint);

  function underlying() external view returns(address);
  function balanceOfUnderlying(address _user) external view returns (uint);
  function underlyingAmount(uint amount) external view returns (uint);
}