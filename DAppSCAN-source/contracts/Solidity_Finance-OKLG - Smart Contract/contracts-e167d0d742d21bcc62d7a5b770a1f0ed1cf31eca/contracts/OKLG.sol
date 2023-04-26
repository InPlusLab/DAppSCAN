/*

ok.let's.go. ($OKLG)

Website = https://oklg.io
Telegram = https://t.me/ok_lg
Twitter = https://twitter.com/oklgio

*/

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import './interfaces/IConditional.sol';

contract OKLG is Context, IERC20, Ownable {
  using SafeMath for uint256;
  using Address for address;

  address payable public treasuryWallet =
    payable(0xDb3AC91239b79Fae75c21E1f75a189b1D75dD906);
  address public constant deadAddress =
    0x000000000000000000000000000000000000dEaD;

  mapping(address => uint256) private _rOwned;
  mapping(address => uint256) private _tOwned;
  mapping(address => mapping(address => uint256)) private _allowances;
  mapping(address => bool) private _isSniper;
  address[] private _confirmedSnipers;

  uint256 public rewardsClaimTimeSeconds = 60 * 60 * 4; // 4 hours
  mapping(address => uint256) private _rewardsLastClaim;

  mapping(address => bool) private _isExcludedFee;
  mapping(address => bool) private _isExcludedReward;
  address[] private _excluded;

  string private constant _name = 'ok.lets.go.';
  string private constant _symbol = 'OKLG';
  uint8 private constant _decimals = 9;

  uint256 private constant MAX = ~uint256(0);
  uint256 private constant _tTotal = 420690000000 * 10**_decimals;
  uint256 private _rTotal = (MAX - (MAX % _tTotal));
  uint256 private _tFeeTotal;

  uint256 public reflectionFee = 2;
  uint256 private _previousReflectFee = reflectionFee;

  uint256 public treasuryFee = 4;
  uint256 private _previousTreasuryFee = treasuryFee;

  uint256 public ethRewardsFee = 2;
  uint256 private _previousETHRewardsFee = ethRewardsFee;
  uint256 public ethRewardsBalance;

  uint256 public buybackFee = 2;
  uint256 private _previousBuybackFee = buybackFee;
  address public buybackTokenAddress = address(this);
  address public buybackReceiver = deadAddress;

  uint256 public feeSellMultiplier = 1;
  uint256 public feeRate = 2;
  uint256 public launchTime;

  uint256 public boostRewardsPercent = 50;

  address public boostRewardsContract;
  address public feeExclusionContract;

  IUniswapV2Router02 public uniswapV2Router;
  address public uniswapV2Pair;
  mapping(address => bool) private _isUniswapPair;

  // PancakeSwap: 0x10ED43C718714eb63d5aA57B78B54704E256024E
  // Uniswap V2: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
  address private constant _uniswapRouterAddress =
    0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

  bool private _inSwapAndLiquify;
  bool private _isSelling;
  bool private _tradingOpen = false;
  bool private _transferOpen = false;

  event SendETHRewards(address to, uint256 amountETH);
  event SendTokenRewards(address to, address token, uint256 amount);
  event SwapETHForTokens(address whereTo, uint256 amountIn, address[] path);
  event SwapTokensForETH(uint256 amountIn, address[] path);
  event SwapAndLiquify(
    uint256 tokensSwappedForEth,
    uint256 ethAddedForLp,
    uint256 tokensAddedForLp
  );

  modifier lockTheSwap() {
    _inSwapAndLiquify = true;
    _;
    _inSwapAndLiquify = false;
  }

  constructor() {
    _rOwned[_msgSender()] = _rTotal;
    emit Transfer(address(0), _msgSender(), _tTotal);
  }

  function initContract() external onlyOwner {
    IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
      _uniswapRouterAddress
    );
    uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
      address(this),
      _uniswapV2Router.WETH()
    );

    uniswapV2Router = _uniswapV2Router;

    _isExcludedFee[owner()] = true;
    _isExcludedFee[address(this)] = true;
  }

  function openTrading() external onlyOwner {
    treasuryFee = _previousTreasuryFee;
    ethRewardsFee = _previousETHRewardsFee;
    reflectionFee = _previousReflectFee;
    buybackFee = _previousBuybackFee;
    _tradingOpen = true;
    _transferOpen = true;
    launchTime = block.timestamp;
  }

  function name() external pure returns (string memory) {
    return _name;
  }

  function symbol() external pure returns (string memory) {
    return _symbol;
  }

  function decimals() external pure returns (uint8) {
    return _decimals;
  }

  function totalSupply() external pure override returns (uint256) {
    return _tTotal;
  }

  function balanceOf(address account) public view override returns (uint256) {
    if (_isExcludedReward[account]) return _tOwned[account];
    return tokenFromReflection(_rOwned[account]);
  }

  function transfer(address recipient, uint256 amount)
    external
    override
    returns (bool)
  {
    _transfer(_msgSender(), recipient, amount);
    return true;
  }

  function allowance(address owner, address spender)
    external
    view
    override
    returns (uint256)
  {
    return _allowances[owner][spender];
  }

  function approve(address spender, uint256 amount)
    external
    override
    returns (bool)
  {
    _approve(_msgSender(), spender, amount);
    return true;
  }

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external override returns (bool) {
    _transfer(sender, recipient, amount);
    _approve(
      sender,
      _msgSender(),
      _allowances[sender][_msgSender()].sub(
        amount,
        'ERC20: transfer amount exceeds allowance'
      )
    );
    return true;
  }

  function increaseAllowance(address spender, uint256 addedValue)
    external
    virtual
    returns (bool)
  {
    _approve(
      _msgSender(),
      spender,
      _allowances[_msgSender()][spender].add(addedValue)
    );
    return true;
  }

  function decreaseAllowance(address spender, uint256 subtractedValue)
    external
    virtual
    returns (bool)
  {
    _approve(
      _msgSender(),
      spender,
      _allowances[_msgSender()][spender].sub(
        subtractedValue,
        'ERC20: decreased allowance below zero'
      )
    );
    return true;
  }

  function getLastETHRewardsClaim(address wallet)
    external
    view
    returns (uint256)
  {
    return _rewardsLastClaim[wallet];
  }

  function totalFees() external view returns (uint256) {
    return _tFeeTotal;
  }

  function deliver(uint256 tAmount) external {
    address sender = _msgSender();
    require(
      !_isExcludedReward[sender],
      'Excluded addresses cannot call this function'
    );
    (uint256 rAmount, , , , , ) = _getValues(sender, tAmount);
    _rOwned[sender] = _rOwned[sender].sub(rAmount);
    _rTotal = _rTotal.sub(rAmount);
    _tFeeTotal = _tFeeTotal.add(tAmount);
  }

  function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
    external
    view
    returns (uint256)
  {
    require(tAmount <= _tTotal, 'Amount must be less than supply');
    if (!deductTransferFee) {
      (uint256 rAmount, , , , , ) = _getValues(address(0), tAmount);
      return rAmount;
    } else {
      (, uint256 rTransferAmount, , , , ) = _getValues(address(0), tAmount);
      return rTransferAmount;
    }
  }

  function tokenFromReflection(uint256 rAmount) public view returns (uint256) {
    require(rAmount <= _rTotal, 'Amount must be less than total reflections');
    uint256 currentRate = _getRate();
    return rAmount.div(currentRate);
  }

  function excludeFromReward(address account) external onlyOwner {
    require(!_isExcludedReward[account], 'Account is already excluded');
    if (_rOwned[account] > 0) {
      _tOwned[account] = tokenFromReflection(_rOwned[account]);
    }
    _isExcludedReward[account] = true;
    _excluded.push(account);
  }

  function includeInReward(address account) external onlyOwner {
    require(_isExcludedReward[account], 'Account is already included');
    for (uint256 i = 0; i < _excluded.length; i++) {
      if (_excluded[i] == account) {
        _excluded[i] = _excluded[_excluded.length - 1];
        _tOwned[account] = 0;
        _isExcludedReward[account] = false;
        _excluded.pop();
        break;
      }
    }
  }

  function _approve(
    address owner,
    address spender,
    uint256 amount
  ) private {
    require(owner != address(0), 'ERC20: approve from the zero address');
    require(spender != address(0), 'ERC20: approve to the zero address');

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  function _transfer(
    address from,
    address to,
    uint256 amount
  ) private {
    require(from != address(0), 'ERC20: transfer from the zero address');
    require(to != address(0), 'ERC20: transfer to the zero address');
    require(amount > 0, 'Transfer amount must be greater than zero');
    require(!_isSniper[to], 'Stop sniping!');
    require(!_isSniper[from], 'Stop sniping!');
    require(!_isSniper[_msgSender()], 'Stop sniping!');
    require(
      _transferOpen || from == owner(),
      'transferring tokens is not currently allowed'
    );

    // reset receiver's timer to prevent users buying and
    // immmediately transferring to buypass timer
    _rewardsLastClaim[to] = block.timestamp;

    bool excludedFromFee = false;

    // buy
    if (
      (from == uniswapV2Pair || _isUniswapPair[from]) &&
      to != address(uniswapV2Router)
    ) {
      // normal buy, check for snipers
      if (!isExcludedFromFee(to)) {
        require(_tradingOpen, 'Trading not yet enabled.');

        // antibot
        if (block.timestamp == launchTime) {
          _isSniper[to] = true;
          _confirmedSnipers.push(to);
        }
        _rewardsLastClaim[from] = block.timestamp;
      } else {
        // set excluded flag for takeFee below since buyer is excluded
        excludedFromFee = true;
      }
    }

    // sell
    if (
      !_inSwapAndLiquify &&
      _tradingOpen &&
      (to == uniswapV2Pair || _isUniswapPair[to])
    ) {
      uint256 _contractTokenBalance = balanceOf(address(this));
      if (_contractTokenBalance > 0) {
        if (
          _contractTokenBalance > balanceOf(uniswapV2Pair).mul(feeRate).div(100)
        ) {
          _contractTokenBalance = balanceOf(uniswapV2Pair).mul(feeRate).div(
            100
          );
        }
        _swapTokens(_contractTokenBalance);
      }
      _rewardsLastClaim[from] = block.timestamp;
      _isSelling = true;
      excludedFromFee = isExcludedFromFee(from);
    }

    bool takeFee = false;

    // take fee only on swaps
    if (
      (from == uniswapV2Pair ||
        to == uniswapV2Pair ||
        _isUniswapPair[to] ||
        _isUniswapPair[from]) && !excludedFromFee
    ) {
      takeFee = true;
    }

    _tokenTransfer(from, to, amount, takeFee);
    _isSelling = false;
  }

  function _swapTokens(uint256 _contractTokenBalance) private lockTheSwap {
    uint256 ethBalanceBefore = address(this).balance;
    _swapTokensForEth(_contractTokenBalance);
    uint256 ethBalanceAfter = address(this).balance;
    uint256 ethBalanceUpdate = ethBalanceAfter.sub(ethBalanceBefore);
    uint256 _liquidityFeeTotal = _liquidityFeeAggregate(address(0));

    ethRewardsBalance += ethBalanceUpdate.mul(ethRewardsFee).div(
      _liquidityFeeTotal
    );

    // send ETH to treasury address
    uint256 treasuryETHBalance = ethBalanceUpdate.mul(treasuryFee).div(
      _liquidityFeeTotal
    );
    if (treasuryETHBalance > 0) {
      _sendETHToTreasury(treasuryETHBalance);
    }

    // buy back
    uint256 buybackETHBalance = ethBalanceUpdate.mul(buybackFee).div(
      _liquidityFeeTotal
    );
    if (buybackETHBalance > 0) {
      _buyBackTokens(buybackETHBalance);
    }
  }

  function _sendETHToTreasury(uint256 amount) private {
    treasuryWallet.call{ value: amount }('');
  }

  function _buyBackTokens(uint256 amount) private {
    // generate the uniswap pair path of token -> weth
    address[] memory path = new address[](2);
    path[0] = uniswapV2Router.WETH();
    path[1] = buybackTokenAddress;

    // make the swap
    uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{
      value: amount
    }(
      0, // accept any amount of tokens
      path,
      buybackReceiver,
      block.timestamp
    );

    emit SwapETHForTokens(buybackReceiver, amount, path);
  }

  function _swapTokensForEth(uint256 tokenAmount) private {
    // generate the uniswap pair path of token -> weth
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = uniswapV2Router.WETH();

    _approve(address(this), address(uniswapV2Router), tokenAmount);

    // make the swap
    uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount,
      0, // accept any amount of ETH
      path,
      address(this), // the contract
      block.timestamp
    );

    emit SwapTokensForETH(tokenAmount, path);
  }

  function _tokenTransfer(
    address sender,
    address recipient,
    uint256 amount,
    bool takeFee
  ) private {
    if (!takeFee) _removeAllFee();

    if (_isExcludedReward[sender] && !_isExcludedReward[recipient]) {
      _transferFromExcluded(sender, recipient, amount);
    } else if (!_isExcludedReward[sender] && _isExcludedReward[recipient]) {
      _transferToExcluded(sender, recipient, amount);
    } else if (_isExcludedReward[sender] && _isExcludedReward[recipient]) {
      _transferBothExcluded(sender, recipient, amount);
    } else {
      _transferStandard(sender, recipient, amount);
    }

    if (!takeFee) _restoreAllFee();
  }

  function _transferStandard(
    address sender,
    address recipient,
    uint256 tAmount
  ) private {
    (
      uint256 rAmount,
      uint256 rTransferAmount,
      uint256 rFee,
      uint256 tTransferAmount,
      uint256 tFee,
      uint256 tLiquidity
    ) = _getValues(sender, tAmount);
    _rOwned[sender] = _rOwned[sender].sub(rAmount);
    _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
    _takeLiquidity(tLiquidity);
    _reflectFee(rFee, tFee);
    emit Transfer(sender, recipient, tTransferAmount);
  }

  function _transferToExcluded(
    address sender,
    address recipient,
    uint256 tAmount
  ) private {
    (
      uint256 rAmount,
      uint256 rTransferAmount,
      uint256 rFee,
      uint256 tTransferAmount,
      uint256 tFee,
      uint256 tLiquidity
    ) = _getValues(sender, tAmount);
    _rOwned[sender] = _rOwned[sender].sub(rAmount);
    _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
    _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
    _takeLiquidity(tLiquidity);
    _reflectFee(rFee, tFee);
    emit Transfer(sender, recipient, tTransferAmount);
  }

  function _transferFromExcluded(
    address sender,
    address recipient,
    uint256 tAmount
  ) private {
    (
      uint256 rAmount,
      uint256 rTransferAmount,
      uint256 rFee,
      uint256 tTransferAmount,
      uint256 tFee,
      uint256 tLiquidity
    ) = _getValues(sender, tAmount);
    _tOwned[sender] = _tOwned[sender].sub(tAmount);
    _rOwned[sender] = _rOwned[sender].sub(rAmount);
    _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
    _takeLiquidity(tLiquidity);
    _reflectFee(rFee, tFee);
    emit Transfer(sender, recipient, tTransferAmount);
  }

  function _transferBothExcluded(
    address sender,
    address recipient,
    uint256 tAmount
  ) private {
    (
      uint256 rAmount,
      uint256 rTransferAmount,
      uint256 rFee,
      uint256 tTransferAmount,
      uint256 tFee,
      uint256 tLiquidity
    ) = _getValues(sender, tAmount);
    _tOwned[sender] = _tOwned[sender].sub(tAmount);
    _rOwned[sender] = _rOwned[sender].sub(rAmount);
    _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
    _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
    _takeLiquidity(tLiquidity);
    _reflectFee(rFee, tFee);
    emit Transfer(sender, recipient, tTransferAmount);
  }

  function _reflectFee(uint256 rFee, uint256 tFee) private {
    _rTotal = _rTotal.sub(rFee);
    _tFeeTotal = _tFeeTotal.add(tFee);
  }

  function _getValues(address seller, uint256 tAmount)
    private
    view
    returns (
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    )
  {
    (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getTValues(
      seller,
      tAmount
    );
    (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
      tAmount,
      tFee,
      tLiquidity,
      _getRate()
    );
    return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tLiquidity);
  }

  function _getTValues(address seller, uint256 tAmount)
    private
    view
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    uint256 tFee = _calculateReflectFee(tAmount);
    uint256 tLiquidity = _calculateLiquidityFee(seller, tAmount);
    uint256 tTransferAmount = tAmount.sub(tFee).sub(tLiquidity);
    return (tTransferAmount, tFee, tLiquidity);
  }

  function _getRValues(
    uint256 tAmount,
    uint256 tFee,
    uint256 tLiquidity,
    uint256 currentRate
  )
    private
    pure
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    uint256 rAmount = tAmount.mul(currentRate);
    uint256 rFee = tFee.mul(currentRate);
    uint256 rLiquidity = tLiquidity.mul(currentRate);
    uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity);
    return (rAmount, rTransferAmount, rFee);
  }

  function _getRate() private view returns (uint256) {
    (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
    return rSupply.div(tSupply);
  }

  function _getCurrentSupply() private view returns (uint256, uint256) {
    uint256 rSupply = _rTotal;
    uint256 tSupply = _tTotal;
    for (uint256 i = 0; i < _excluded.length; i++) {
      if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply)
        return (_rTotal, _tTotal);
      rSupply = rSupply.sub(_rOwned[_excluded[i]]);
      tSupply = tSupply.sub(_tOwned[_excluded[i]]);
    }
    if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
    return (rSupply, tSupply);
  }

  function _takeLiquidity(uint256 tLiquidity) private {
    uint256 currentRate = _getRate();
    uint256 rLiquidity = tLiquidity.mul(currentRate);
    _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
    if (_isExcludedReward[address(this)])
      _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
  }

  function _calculateReflectFee(uint256 _amount)
    private
    view
    returns (uint256)
  {
    return _amount.mul(reflectionFee).div(10**2);
  }

  function _liquidityFeeAggregate(address seller)
    private
    view
    returns (uint256)
  {
    uint256 feeMultiplier = _isSelling && !canClaimRewards(seller)
      ? feeSellMultiplier
      : 1;
    return (treasuryFee.add(ethRewardsFee).add(buybackFee)).mul(feeMultiplier);
  }

  function _calculateLiquidityFee(address seller, uint256 _amount)
    private
    view
    returns (uint256)
  {
    return _amount.mul(_liquidityFeeAggregate(seller)).div(10**2);
  }

  function _removeAllFee() private {
    if (
      reflectionFee == 0 &&
      treasuryFee == 0 &&
      ethRewardsFee == 0 &&
      buybackFee == 0
    ) return;

    _previousReflectFee = reflectionFee;
    _previousTreasuryFee = treasuryFee;
    _previousETHRewardsFee = ethRewardsFee;
    _previousBuybackFee = buybackFee;

    reflectionFee = 0;
    treasuryFee = 0;
    ethRewardsFee = 0;
    buybackFee = 0;
  }

  function _restoreAllFee() private {
    reflectionFee = _previousReflectFee;
    treasuryFee = _previousTreasuryFee;
    ethRewardsFee = _previousETHRewardsFee;
    buybackFee = _previousBuybackFee;
  }

  function getSellSlippage(address seller) external view returns (uint256) {
    uint256 feeAgg = reflectionFee.add(treasuryFee).add(ethRewardsFee).add(
      buybackFee
    );
    return
      isExcludedFromFee(seller) ? 0 : !canClaimRewards(seller)
        ? feeAgg.mul(feeSellMultiplier)
        : feeAgg;
  }

  function isUniswapPair(address _pair) external view returns (bool) {
    if (_pair == uniswapV2Pair) return true;
    return _isUniswapPair[_pair];
  }

  function eligibleForRewardBooster(address wallet) public view returns (bool) {
    return
      boostRewardsContract != address(0) &&
      IConditional(boostRewardsContract).passesTest(wallet);
  }

  function isExcludedFromFee(address account) public view returns (bool) {
    return
      _isExcludedFee[account] ||
      (feeExclusionContract != address(0) &&
        IConditional(feeExclusionContract).passesTest(account));
  }

  function isExcludedFromReward(address account) external view returns (bool) {
    return _isExcludedReward[account];
  }

  function excludeFromFee(address account) external onlyOwner {
    _isExcludedFee[account] = true;
  }

  function includeInFee(address account) external onlyOwner {
    _isExcludedFee[account] = false;
  }

  function setRewardsClaimTimeSeconds(uint256 _seconds) external onlyOwner {
    rewardsClaimTimeSeconds = _seconds;
  }

  function setReflectionFeePercent(uint256 _newFee) external onlyOwner {
    require(_newFee <= 10, 'fee cannot exceed 10%');
    reflectionFee = _newFee;
  }

  function setTreasuryFeePercent(uint256 _newFee) external onlyOwner {
    require(_newFee <= 10, 'fee cannot exceed 10%');
    treasuryFee = _newFee;
  }

  function setETHRewardsFeeFeePercent(uint256 _newFee) external onlyOwner {
    require(_newFee <= 10, 'fee cannot exceed 10%');
    ethRewardsFee = _newFee;
  }

  function setBuybackFeePercent(uint256 _newFee) external onlyOwner {
    require(_newFee <= 10, 'fee cannot exceed 10%');
    buybackFee = _newFee;
  }

  function setFeeSellMultiplier(uint256 multiplier) external onlyOwner {
    require(
      multiplier > 0 && multiplier <= 5,
      'must be greater than 0 and less than or equal to 5'
    );
    require(
      _liquidityFeeAggregate(address(0)).mul(multiplier) < 40,
      'multiplier should not make total fee more than 40%'
    );
    feeSellMultiplier = multiplier;
  }

  function setTreasuryAddress(address _treasuryWallet) external onlyOwner {
    treasuryWallet = payable(_treasuryWallet);
  }

  function setBuybackTokenAddress(address _tokenAddress) external onlyOwner {
    buybackTokenAddress = _tokenAddress;
  }

  function setBuybackReceiver(address _receiver) external onlyOwner {
    buybackReceiver = _receiver;
  }

  function addUniswapPair(address _pair) external onlyOwner {
    _isUniswapPair[_pair] = true;
  }

  function removeUniswapPair(address _pair) external onlyOwner {
    _isUniswapPair[_pair] = false;
  }

  function setCanTransfer(bool _canTransfer) external onlyOwner {
    _transferOpen = _canTransfer;
  }

  function setBoostRewardsPercent(uint256 perc) external onlyOwner {
    boostRewardsPercent = perc;
  }

  function setBoostRewardsContract(address _contract) external onlyOwner {
    if (_contract != address(0)) {
      IConditional _contCheck = IConditional(_contract);
      // allow setting to zero address to effectively turn off check logic
      require(
        _contCheck.passesTest(address(0)) == true ||
          _contCheck.passesTest(address(0)) == false,
        'contract does not implement interface'
      );
    }
    boostRewardsContract = _contract;
  }

  function setFeeExclusionContract(address _contract) external onlyOwner {
    if (_contract != address(0)) {
      IConditional _contCheck = IConditional(_contract);
      // allow setting to zero address to effectively turn off check logic
      require(
        _contCheck.passesTest(address(0)) == true ||
          _contCheck.passesTest(address(0)) == false,
        'contract does not implement interface'
      );
    }
    feeExclusionContract = _contract;
  }

  function isRemovedSniper(address account) external view returns (bool) {
    return _isSniper[account];
  }

  function removeSniper(address account) external onlyOwner {
    require(account != _uniswapRouterAddress, 'We can not blacklist Uniswap');
    require(!_isSniper[account], 'Account is already blacklisted');
    _isSniper[account] = true;
    _confirmedSnipers.push(account);
  }

  function amnestySniper(address account) external onlyOwner {
    require(_isSniper[account], 'Account is not blacklisted');
    for (uint256 i = 0; i < _confirmedSnipers.length; i++) {
      if (_confirmedSnipers[i] == account) {
        _confirmedSnipers[i] = _confirmedSnipers[_confirmedSnipers.length - 1];
        _isSniper[account] = false;
        _confirmedSnipers.pop();
        break;
      }
    }
  }

  function calculateETHRewards(address wallet) public view returns (uint256) {
    uint256 baseRewards = ethRewardsBalance.mul(balanceOf(wallet)).div(
      _tTotal.sub(balanceOf(deadAddress)) // circulating supply
    );
    uint256 rewardsWithBooster = eligibleForRewardBooster(wallet)
      ? baseRewards.add(baseRewards.mul(boostRewardsPercent).div(10**2))
      : baseRewards;
    return
      rewardsWithBooster > ethRewardsBalance ? baseRewards : rewardsWithBooster;
  }

  function calculateTokenRewards(address wallet, address tokenAddress)
    public
    view
    returns (uint256)
  {
    IERC20 token = IERC20(tokenAddress);
    uint256 contractTokenBalance = token.balanceOf(address(this));
    uint256 baseRewards = contractTokenBalance.mul(balanceOf(wallet)).div(
      _tTotal.sub(balanceOf(deadAddress)) // circulating supply
    );
    uint256 rewardsWithBooster = eligibleForRewardBooster(wallet)
      ? baseRewards.add(baseRewards.mul(boostRewardsPercent).div(10**2))
      : baseRewards;
    return
      rewardsWithBooster > contractTokenBalance
        ? baseRewards
        : rewardsWithBooster;
  }

  function claimETHRewards() external {
    require(
      balanceOf(_msgSender()) > 0,
      'You must have a balance to claim ETH rewards'
    );
    require(
      canClaimRewards(_msgSender()),
      'Must wait claim period before claiming rewards'
    );
    _rewardsLastClaim[_msgSender()] = block.timestamp;

    uint256 rewardsSent = calculateETHRewards(_msgSender());
    ethRewardsBalance -= rewardsSent;
    _msgSender().call{ value: rewardsSent }('');
    emit SendETHRewards(_msgSender(), rewardsSent);
  }

  function canClaimRewards(address user) public view returns (bool) {
    return
      block.timestamp > _rewardsLastClaim[user].add(rewardsClaimTimeSeconds);
  }

  function claimTokenRewards(address token) external {
    require(
      balanceOf(_msgSender()) > 0,
      'You must have a balance to claim rewards'
    );
    require(
      IERC20(token).balanceOf(address(this)) > 0,
      'We must have a token balance to claim rewards'
    );
    require(
      canClaimRewards(_msgSender()),
      'Must wait claim period before claiming rewards'
    );
    _rewardsLastClaim[_msgSender()] = block.timestamp;

    uint256 rewardsSent = calculateTokenRewards(_msgSender(), token);
    IERC20(token).transfer(_msgSender(), rewardsSent);
    emit SendTokenRewards(_msgSender(), token, rewardsSent);
  }

  function setFeeRate(uint256 _rate) external onlyOwner {
    feeRate = _rate;
  }

  function emergencyWithdraw() external onlyOwner {
    payable(owner()).call{ value: address(this).balance }('');
  }

  // to recieve ETH from uniswapV2Router when swaping
  receive() external payable {}
}
