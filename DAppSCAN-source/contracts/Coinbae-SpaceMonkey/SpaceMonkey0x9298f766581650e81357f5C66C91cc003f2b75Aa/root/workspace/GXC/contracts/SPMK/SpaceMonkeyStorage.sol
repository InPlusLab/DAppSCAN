// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../library/Address.sol";
import "../library/Ownable.sol";
import '../library/PCS.sol';

contract SpaceMonkeyStorage is Context, Ownable {
  using Address for address;

  // P2E wallet
  address payable public marketingAddress = payable(0x26069eCb652A50BAb6ce1dD527a41bB6674D7276);
  address payable public teamAddress = payable(0xf39E43816107eaC5eC75AFFf5d2a3916515dDa28);
  address _secondOwner = 0xf39E43816107eaC5eC75AFFf5d2a3916515dDa28;
  address public immutable deadAddress = 0x000000000000000000000000000000000000dEaD;
  mapping(address => uint256) internal _rOwned;
  mapping(address => uint256) internal _tOwned;
  mapping(address => mapping(address => uint256)) internal _allowances;
  mapping(address => bool) internal _isBlacklisted;
  mapping(address => bool) internal _isSwap; // for future use, to support multiple LPs
  address[] internal _confirmedSnipers;

  mapping(address => bool) internal _isExcludedFromFee;
  mapping(address => bool) internal _isExcluded;
  address[] internal _excluded;

  string internal _name = 'SpaceMonkey';
  string internal _symbol = 'SPMK';
  uint8 internal _decimals = 9;

  uint256 internal constant MAX = ~uint256(0);
  uint256 internal _tTotal = 1000000000000 * 10**_decimals;
  uint256 public _supplyToStopBurning = 1000000000000 * 10**_decimals;
  uint256 internal _rTotal = (MAX - (MAX % _tTotal));
  uint256 internal _tFeeTotal;

  uint256 public _taxFee = 3;
  uint256 internal _previousTaxFee = _taxFee;

  uint256 public _liquidityFee = 7;
  uint256 internal _previousLiquidityFee = _liquidityFee;
  uint256 public _feemultiplier = 200;
  uint256 public _teamLiquidityFee = 714;
  uint256 public _marketingLiquidityFee = 286;

  uint256 public _burnFee = 0;
  uint256 internal _previousBurnFee = _burnFee;

  uint256 internal _maxPriceImpPerc = 2;

  uint256 internal _maxBuyPercent = 1;
  uint256 internal _maxBuySeconds = 2 * 60 * 60; // 2 hours in seconds after launch
  bool public overrideMaxBuy = true;

  uint256 public launchTime;

  bool inSwapAndLiquify;

  bool tradingOpen = false;

  event SwapETHForTokens(uint256 amountIn, address[] path);

  event SwapTokensForETH(uint256 amountIn, address[] path);

  modifier lockTheSwap() {
    inSwapAndLiquify = true;
    _;
    inSwapAndLiquify = false;
  }

}