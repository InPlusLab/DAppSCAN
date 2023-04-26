// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IProvider.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/dydx/ISoloMargin.sol";
import "../libraries/LibUniversalERC20.sol";

contract HelperFunct {
  /**
   * @dev get Dydx Solo Address
   */
  function getDydxAddress() public pure returns (address addr) {
    addr = 0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e;
  }

  /**
   * @dev get WETH address
   */
  function getWETHAddr() public pure returns (address weth) {
    weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  }

  /**
   * @dev Return ethereum address
   */
  function _getEthAddr() internal pure returns (address) {
    return 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // ETH Address
  }

  /**
   * @dev Get Dydx Market ID from token Address
   */
  function _getMarketId(ISoloMargin _solo, address _token)
    internal
    view
    returns (uint256 _marketId)
  {
    uint256 markets = _solo.getNumMarkets();
    address token = _token == _getEthAddr() ? getWETHAddr() : _token;
    bool check = false;
    for (uint256 i = 0; i < markets; i++) {
      if (token == _solo.getMarketTokenAddress(i)) {
        _marketId = i;
        check = true;
        break;
      }
    }
    require(check, "DYDX Market doesnt exist!");
  }

  /**
   * @dev Get Dydx Acccount arg
   */
  function _getAccountArgs() internal view returns (Account.Info[] memory) {
    Account.Info[] memory accounts = new Account.Info[](1);
    accounts[0] = (Account.Info(address(this), 0));
    return accounts;
  }

  /**
   * @dev Get Dydx Actions args.
   */
  function _getActionsArgs(
    uint256 _marketId,
    uint256 _amt,
    bool _sign
  ) internal view returns (Actions.ActionArgs[] memory) {
    Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](1);
    Types.AssetAmount memory amount = Types.AssetAmount(
      _sign,
      Types.AssetDenomination.Wei,
      Types.AssetReference.Delta,
      _amt
    );
    bytes memory empty;
    Actions.ActionType action = _sign ? Actions.ActionType.Deposit : Actions.ActionType.Withdraw;
    actions[0] = Actions.ActionArgs(action, 0, amount, _marketId, 0, address(this), 0, empty);
    return actions;
  }
}

contract ProviderDYDX is IProvider, HelperFunct {
  using LibUniversalERC20 for IERC20;

  bool public donothing = true;

  //Provider Core Functions

  /**
   * @dev Deposit ETH/ERC20_Token.
   * @param _asset: token address to deposit. (For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
   * @param _amount: token amount to deposit.
   */
  function deposit(address _asset, uint256 _amount) external payable override {
    ISoloMargin dydxContract = ISoloMargin(getDydxAddress());

    uint256 marketId = _getMarketId(dydxContract, _asset);

    if (_asset == _getEthAddr()) {
      IWETH tweth = IWETH(getWETHAddr());
      tweth.deposit{ value: _amount }();
      tweth.approve(getDydxAddress(), _amount);
    } else {
      IWETH tweth = IWETH(_asset);
      tweth.approve(getDydxAddress(), _amount);
    }

    dydxContract.operate(_getAccountArgs(), _getActionsArgs(marketId, _amount, true));
  }

  /**
   * @dev Withdraw ETH/ERC20_Token.
   * @param _asset: token address to withdraw. (For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
   * @param _amount: token amount to withdraw.
   */
  function withdraw(address _asset, uint256 _amount) external payable override {
    ISoloMargin dydxContract = ISoloMargin(getDydxAddress());

    uint256 marketId = _getMarketId(dydxContract, _asset);

    dydxContract.operate(_getAccountArgs(), _getActionsArgs(marketId, _amount, false));

    if (_asset == _getEthAddr()) {
      IWETH tweth = IWETH(getWETHAddr());

      tweth.approve(address(tweth), _amount);

      tweth.withdraw(_amount);
    }
  }

  /**
   * @dev Borrow ETH/ERC20_Token.
   * @param _asset token address to borrow.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
   * @param _amount: token amount to borrow.
   */
  function borrow(address _asset, uint256 _amount) external payable override {
    ISoloMargin dydxContract = ISoloMargin(getDydxAddress());

    uint256 marketId = _getMarketId(dydxContract, _asset);

    dydxContract.operate(_getAccountArgs(), _getActionsArgs(marketId, _amount, false));

    if (_asset == _getEthAddr()) {
      IWETH tweth = IWETH(getWETHAddr());

      tweth.approve(address(_asset), _amount);

      tweth.withdraw(_amount);
    }
  }

  /**
   * @dev Payback borrowed ETH/ERC20_Token.
   * @param _asset token address to payback.(For ETH: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)
   * @param _amount: token amount to payback.
   */
  function payback(address _asset, uint256 _amount) external payable override {
    ISoloMargin dydxContract = ISoloMargin(getDydxAddress());

    uint256 marketId = _getMarketId(dydxContract, _asset);

    if (_asset == _getEthAddr()) {
      IWETH tweth = IWETH(getWETHAddr());
      tweth.deposit{ value: _amount }();
      tweth.approve(getDydxAddress(), _amount);
    } else {
      IWETH tweth = IWETH(_asset);
      tweth.approve(getDydxAddress(), _amount);
    }

    dydxContract.operate(_getAccountArgs(), _getActionsArgs(marketId, _amount, true));
  }

  /**
   * @dev Returns the current borrowing rate (APR) of a ETH/ERC20_Token, in ray(1e27).
   * @param _asset: token address to query the current borrowing rate.
   */
  function getBorrowRateFor(address _asset) external view override returns (uint256) {
    ISoloMargin dydxContract = ISoloMargin(getDydxAddress());
    uint256 marketId = _getMarketId(dydxContract, _asset);

    ISoloMargin.Rate memory _rate = dydxContract.getMarketInterestRate(marketId);

    return (_rate.value) * 1e9 * 365 days;
  }

  /**
   * @dev Returns the borrow balance of a ETH/ERC20_Token.
   * @param _asset: token address to query the balance.
   */
  function getBorrowBalance(address _asset) external view override returns (uint256) {
    ISoloMargin dydxContract = ISoloMargin(getDydxAddress());
    uint256 marketId = _getMarketId(dydxContract, _asset);
    Account.Info memory account = Account.Info({ owner: msg.sender, number: 0 });
    ISoloMargin.Wei memory structbalance = dydxContract.getAccountWei(account, marketId);

    return structbalance.value;
  }

  /**
   * @dev Returns the borrow balance of a ETH/ERC20_Token.
   * @param _asset: token address to query the balance.
   * @param _who: address of the account.
   */
  function getBorrowBalanceOf(address _asset, address _who)
    external
    view
    override
    returns (uint256)
  {
    ISoloMargin dydxContract = ISoloMargin(getDydxAddress());
    uint256 marketId = _getMarketId(dydxContract, _asset);
    Account.Info memory account = Account.Info({ owner: _who, number: 0 });
    ISoloMargin.Wei memory structbalance = dydxContract.getAccountWei(account, marketId);

    return structbalance.value;
  }

  /**
   * @dev Returns the borrow balance of a ETH/ERC20_Token.
   * @param _asset: token address to query the balance.
   */
  function getDepositBalance(address _asset) external view override returns (uint256) {
    ISoloMargin dydxContract = ISoloMargin(getDydxAddress());
    uint256 marketId = _getMarketId(dydxContract, _asset);

    Account.Info memory account = Account.Info({ owner: msg.sender, number: 0 });
    ISoloMargin.Wei memory structbalance = dydxContract.getAccountWei(account, marketId);

    return structbalance.value;
  }
}
