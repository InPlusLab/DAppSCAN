// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IProvider.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/aave/IAaveDataProvider.sol";
import "../interfaces/aave/IAaveLendingPool.sol";
import "../interfaces/aave/IAaveLendingPoolProvider.sol";
import "../libraries/LibUniversalERC20.sol";

contract ProviderAave is IProvider {
  using LibUniversalERC20 for IERC20;

  function _getAaveProvider() internal pure returns (IAaveLendingPoolProvider) {
    return IAaveLendingPoolProvider(0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5);
  }

  function _getAaveDataProvider() internal pure returns (IAaveDataProvider) {
    return IAaveDataProvider(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d);
  }

  function _getWethAddr() internal pure returns (address) {
    return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  }

  function _getEthAddr() internal pure returns (address) {
    return 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  }

  /**
   * @dev Return the borrowing rate of ETH/ERC20_Token.
   * @param _asset to query the borrowing rate.
   */
  function getBorrowRateFor(address _asset) external view override returns (uint256) {
    IAaveDataProvider aaveData = _getAaveDataProvider();

    (, , , , uint256 variableBorrowRate, , , , , ) = IAaveDataProvider(aaveData).getReserveData(
      _asset == _getEthAddr() ? _getWethAddr() : _asset
    );

    return variableBorrowRate;
  }

  /**
   * @dev Return borrow balance of ETH/ERC20_Token.
   * @param _asset token address to query the balance.
   */
  function getBorrowBalance(address _asset) external view override returns (uint256) {
    IAaveDataProvider aaveData = _getAaveDataProvider();

    bool isEth = _asset == _getEthAddr();
    address _tokenAddr = isEth ? _getWethAddr() : _asset;

    (, , uint256 variableDebt, , , , , , ) = aaveData.getUserReserveData(_tokenAddr, msg.sender);

    return variableDebt;
  }

  /**
   * @dev Return borrow balance of ETH/ERC20_Token.
   * @param _asset token address to query the balance.
   * @param _who address of the account.
   */
  function getBorrowBalanceOf(address _asset, address _who)
    external
    view
    override
    returns (uint256)
  {
    IAaveDataProvider aaveData = _getAaveDataProvider();

    bool isEth = _asset == _getEthAddr();
    address _tokenAddr = isEth ? _getWethAddr() : _asset;

    (, , uint256 variableDebt, , , , , , ) = aaveData.getUserReserveData(_tokenAddr, _who);

    return variableDebt;
  }

  /**
   * @dev Return deposit balance of ETH/ERC20_Token.
   * @param _asset token address to query the balance.
   */
  function getDepositBalance(address _asset) external view override returns (uint256) {
    IAaveDataProvider aaveData = _getAaveDataProvider();

    bool isEth = _asset == _getEthAddr();
    address _tokenAddr = isEth ? _getWethAddr() : _asset;

    (uint256 atokenBal, , , , , , , , ) = aaveData.getUserReserveData(_tokenAddr, msg.sender);

    return atokenBal;
  }

  /**
   * @dev Deposit ETH/ERC20_Token.
   * @param _asset token address to deposit.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
   * @param _amount token amount to deposit.
   */
  function deposit(address _asset, uint256 _amount) external payable override {
    IAaveLendingPool aave = IAaveLendingPool(_getAaveProvider().getLendingPool());

    bool isEth = _asset == _getEthAddr();
    address _tokenAddr = isEth ? _getWethAddr() : _asset;

    // convert ETH to WETH
    if (isEth) IWETH(_tokenAddr).deposit{ value: _amount }();

    IERC20(_tokenAddr).univApprove(address(aave), _amount);

    aave.deposit(_tokenAddr, _amount, address(this), 0);

    aave.setUserUseReserveAsCollateral(_tokenAddr, true);
  }

  /**
   * @dev Borrow ETH/ERC20_Token.
   * @param _asset token address to borrow.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
   * @param _amount token amount to borrow.
   */
  function borrow(address _asset, uint256 _amount) external payable override {
    IAaveLendingPool aave = IAaveLendingPool(_getAaveProvider().getLendingPool());

    bool isEth = _asset == _getEthAddr();
    address _tokenAddr = isEth ? _getWethAddr() : _asset;

    aave.borrow(_tokenAddr, _amount, 2, 0, address(this));

    // convert WETH to ETH
    if (isEth) IWETH(_tokenAddr).withdraw(_amount);
  }

  /**
   * @dev Withdraw ETH/ERC20_Token.
   * @param _asset token address to withdraw.
   * @param _amount token amount to withdraw.
   */
  function withdraw(address _asset, uint256 _amount) external payable override {
    IAaveLendingPool aave = IAaveLendingPool(_getAaveProvider().getLendingPool());

    bool isEth = _asset == _getEthAddr();
    address _tokenAddr = isEth ? _getWethAddr() : _asset;

    aave.withdraw(_tokenAddr, _amount, address(this));

    // convert WETH to ETH
    if (isEth) IWETH(_tokenAddr).withdraw(_amount);
  }

  /**
   * @dev Payback borrowed ETH/ERC20_Token.
   * @param _asset token address to payback.
   * @param _amount token amount to payback.
   */

  function payback(address _asset, uint256 _amount) external payable override {
    IAaveLendingPool aave = IAaveLendingPool(_getAaveProvider().getLendingPool());

    bool isEth = _asset == _getEthAddr();
    address _tokenAddr = isEth ? _getWethAddr() : _asset;

    // convert ETH to WETH
    if (isEth) IWETH(_tokenAddr).deposit{ value: _amount }();

    IERC20(_tokenAddr).univApprove(address(aave), _amount);

    aave.repay(_tokenAddr, _amount, 2, address(this));
  }
}
