// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IProvider.sol";
import "../interfaces/compound/IGenCToken.sol";
import "../interfaces/compound/ICErc20.sol";
import "../interfaces/compound/ICEth.sol";
import "../interfaces/compound/IFuseComptroller.sol";
import "../libraries/LibUniversalERC20.sol";

contract HelperFunct {
  function _isETH(address token) internal pure returns (bool) {
    return (token == address(0) || token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
  }

  function _getComptrollerAddress() internal pure returns (address) {
    return 0x621579DD26774022F33147D3852ef4E00024b763;
  }

  function _getCTokenAddr(address _asset) internal view returns (address cTokenAddr) {
    if (_isETH(_asset)) {
      // Rari Fuse ETH is 0x0000000000000000000000000000000000000000
      cTokenAddr = IFuseComptroller(_getComptrollerAddress()).cTokensByUnderlying(
        0x0000000000000000000000000000000000000000
      );
    } else {
      cTokenAddr = IFuseComptroller(_getComptrollerAddress()).cTokensByUnderlying(_asset);
    }
  }

  //Compound functions

  /**
   * @dev Approves vault's assets as collateral for Compound Protocol.
   * @param _cTokenAddress: asset type to be approved as collateral.
   */
  function _enterCollatMarket(address _cTokenAddress) internal {
    // Create a reference to the corresponding network Comptroller
    IFuseComptroller comptroller = IFuseComptroller(_getComptrollerAddress());

    address[] memory cTokenMarkets = new address[](1);
    cTokenMarkets[0] = _cTokenAddress;
    comptroller.enterMarkets(cTokenMarkets);
  }

  /**
   * @dev Removes vault's assets as collateral for Compound Protocol.
   * @param _cTokenAddress: asset type to be removed as collateral.
   */
  function _exitCollatMarket(address _cTokenAddress) internal {
    // Create a reference to the corresponding network Comptroller
    IFuseComptroller comptroller = IFuseComptroller(_getComptrollerAddress());

    comptroller.exitMarket(_cTokenAddress);
  }
}

contract ProviderFuse18 is IProvider, HelperFunct {
  using LibUniversalERC20 for IERC20;

  //Provider Core Functions

  /**
   * @dev Deposit ETH/ERC20_Token.
   * @param _asset: token address to deposit. (For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
   * @param _amount: token amount to deposit.
   */
  function deposit(address _asset, uint256 _amount) external payable override {
    //Get cToken address from mapping
    address cTokenAddr = _getCTokenAddr(_asset);

    //Enter and/or ensure collateral market is enacted
    _enterCollatMarket(cTokenAddr);

    if (_isETH(_asset)) {
      // Create a reference to the cToken contract
      ICEth cToken = ICEth(cTokenAddr);

      //Compound protocol Mints cTokens, ETH method
      cToken.mint{ value: _amount }();
    } else {
      // Create reference to the ERC20 contract
      IERC20 erc20token = IERC20(_asset);

      // Create a reference to the cToken contract
      ICErc20 cToken = ICErc20(cTokenAddr);

      //Checks, Vault balance of ERC20 to make deposit
      require(erc20token.balanceOf(address(this)) >= _amount, "Not enough Balance");

      //Approve to move ERC20tokens
      erc20token.univApprove(address(cTokenAddr), _amount);

      // Compound Protocol mints cTokens, trhow error if not
      require(cToken.mint(_amount) == 0, "Deposit-failed");
    }
  }

  /**
   * @dev Withdraw ETH/ERC20_Token.
   * @param _asset: token address to withdraw. (For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
   * @param _amount: token amount to withdraw.
   */
  function withdraw(address _asset, uint256 _amount) external payable override {
    //Get cToken address from mapping
    address cTokenAddr = _getCTokenAddr(_asset);

    // Create a reference to the corresponding cToken contract
    IGenCToken cToken = IGenCToken(cTokenAddr);

    //Compound Protocol Redeem Process, throw errow if not.
    require(cToken.redeemUnderlying(_amount) == 0, "Withdraw-failed");
  }

  /**
   * @dev Borrow ETH/ERC20_Token.
   * @param _asset token address to borrow.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
   * @param _amount: token amount to borrow.
   */
  function borrow(address _asset, uint256 _amount) external payable override {
    //Get cToken address from mapping
    address cTokenAddr = _getCTokenAddr(_asset);

    // Create a reference to the corresponding cToken contract
    IGenCToken cToken = IGenCToken(cTokenAddr);

    //Enter and/or ensure collateral market is enacted
    //_enterCollatMarket(cTokenAddr);

    //Compound Protocol Borrow Process, throw errow if not.
    require(cToken.borrow(_amount) == 0, "borrow-failed");
  }

  /**
   * @dev Payback borrowed ETH/ERC20_Token.
   * @param _asset token address to payback.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
   * @param _amount: token amount to payback.
   */
  function payback(address _asset, uint256 _amount) external payable override {
    //Get cToken address from mapping
    address cTokenAddr = _getCTokenAddr(_asset);

    if (_isETH(_asset)) {
      // Create a reference to the corresponding cToken contract
      ICEth cToken = ICEth(cTokenAddr);

      cToken.repayBorrow{ value: msg.value }();
    } else {
      // Create reference to the ERC20 contract
      IERC20 erc20token = IERC20(_asset);

      // Create a reference to the corresponding cToken contract
      ICErc20 cToken = ICErc20(cTokenAddr);

      // Check there is enough balance to pay
      require(erc20token.balanceOf(address(this)) >= _amount, "Not-enough-token");
      erc20token.univApprove(address(cTokenAddr), _amount);
      cToken.repayBorrow(_amount);
    }
  }

  /**
   * @dev Returns the current borrowing rate (APR) of a ETH/ERC20_Token, in ray(1e27).
   * @param _asset: token address to query the current borrowing rate.
   */
  function getBorrowRateFor(address _asset) external view override returns (uint256) {
    address cTokenAddr = _getCTokenAddr(_asset);

    //Block Rate transformed for common mantissa for Fuji in ray (1e27), Note: Compound uses base 1e18
    uint256 bRateperBlock = IGenCToken(cTokenAddr).borrowRatePerBlock() * 10**9;

    // The approximate number of blocks per year that is assumed by the Compound interest rate model
    uint256 blocksperYear = 2102400;
    return bRateperBlock * blocksperYear;
  }

  /**
   * @dev Returns the borrow balance of a ETH/ERC20_Token.
   * @param _asset: token address to query the balance.
   */
  function getBorrowBalance(address _asset) external view override returns (uint256) {
    address cTokenAddr = _getCTokenAddr(_asset);

    return IGenCToken(cTokenAddr).borrowBalanceStored(msg.sender);
  }

  /**
   * @dev Return borrow balance of ETH/ERC20_Token.
   * This function is the accurate way to get Compound borrow balance.
   * It costs ~84K gas and is not a view function.
   * @param _asset token address to query the balance.
   * @param _who address of the account.
   */
  function getBorrowBalanceOf(address _asset, address _who) external override returns (uint256) {
    address cTokenAddr = _getCTokenAddr(_asset);

    return IGenCToken(cTokenAddr).borrowBalanceCurrent(_who);
  }

  /**
   * @dev Returns the deposit balance of a ETH/ERC20_Token.
   * @param _asset: token address to query the balance.
   */
  function getDepositBalance(address _asset) external view override returns (uint256) {
    address cTokenAddr = _getCTokenAddr(_asset);
    uint256 cTokenBal = IGenCToken(cTokenAddr).balanceOf(msg.sender);
    uint256 exRate = IGenCToken(cTokenAddr).exchangeRateStored();

    return (exRate * cTokenBal) / 1e18;
  }
}
