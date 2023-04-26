// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IVault {
  // Events

  // Log Users Deposit
  event Deposit(address indexed userAddrs, address indexed asset, uint256 amount);
  // Log Users withdraw
  event Withdraw(address indexed userAddrs, address indexed asset, uint256 amount);
  // Log Users borrow
  event Borrow(address indexed userAddrs, address indexed asset, uint256 amount);
  // Log Users debt repay
  event Payback(address indexed userAddrs, address indexed asset, uint256 amount);

  // Log New active provider
  event SetActiveProvider(address providerAddr);
  // Log Switch providers
  event Switch(
    address fromProviderAddrs,
    address toProviderAddr,
    uint256 debtamount,
    uint256 collattamount
  );

  // Core Vault Functions

  function deposit(uint256 _collateralAmount) external payable;

  function withdraw(int256 _withdrawAmount) external;

  function withdrawLiq(int256 _withdrawAmount) external;

  function borrow(uint256 _borrowAmount) external;

  function payback(int256 _repayAmount) external payable;

  function paybackLiq(address[] memory _users, uint256 _repayAmount) external payable;

  function executeSwitch(
    address _newProvider,
    uint256 _flashLoanDebt,
    uint256 _fee
  ) external payable;

  //Getter Functions

  function activeProvider() external view returns (address);

  function borrowBalance(address _provider) external view returns (uint256);

  function depositBalance(address _provider) external view returns (uint256);

  function userDebtBalance(address _user) external view returns (uint256);

  function userProtocolFee(address _user) external view returns (uint256);

  function userDepositBalance(address _user) external view returns (uint256);

  function getNeededCollateralFor(uint256 _amount, bool _withFactors)
    external
    view
    returns (uint256);

  function getLiquidationBonusFor(uint256 _amount) external view returns (uint256);

  function getProviders() external view returns (address[] memory);

  function fujiERC1155() external view returns (address);

  //Setter Functions

  function setActiveProvider(address _provider) external;

  function updateF1155Balances() external;

  function protocolFee() external view returns (uint64, uint64);
}
