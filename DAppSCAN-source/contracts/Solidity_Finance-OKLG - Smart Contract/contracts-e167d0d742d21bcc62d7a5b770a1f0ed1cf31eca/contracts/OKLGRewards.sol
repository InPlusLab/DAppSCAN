// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import './interfaces/IConditional.sol';
import './interfaces/IMultiplier.sol';
import './OKLGWithdrawable.sol';

interface IOKLG is IERC20 {
  function getLastETHRewardsClaim(address wallet)
    external
    view
    returns (uint256);
}

contract OKLGRewards is OKLGWithdrawable {
  using SafeMath for uint256;

  address public constant deadAddress =
    0x000000000000000000000000000000000000dEaD;
  IOKLG private _oklg = IOKLG(0x5f67df361f568e185aA0304A57bdE4b8028d059E);

  uint256 public rewardsClaimTimeSeconds = 60 * 60 * 12; // 12 hours
  mapping(address => uint256) private _rewardsLastClaim;

  uint256 public boostRewardsPercent = 50;
  address public boostRewardsMultiplierContract;
  address public boostRewardsContract;

  event SendETHRewards(address to, uint256 amountETH);
  event SendTokenRewards(address to, address token, uint256 amount);

  function ethRewardsBalance() external view returns (uint256) {
    return address(this).balance;
  }

  function getLastETHRewardsClaim(address wallet)
    external
    view
    returns (uint256)
  {
    return
      _rewardsLastClaim[wallet] > _oklg.getLastETHRewardsClaim(wallet)
        ? _rewardsLastClaim[wallet]
        : _oklg.getLastETHRewardsClaim(wallet);
  }

  function setBoostMultiplierContract(address _contract) external onlyOwner {
    if (_contract != address(0)) {
      IMultiplier _contCheck = IMultiplier(_contract);
      // allow setting to zero address to effectively turn off check logic
      require(
        _contCheck.getMultiplier(address(0)) >= 0,
        'contract does not implement interface'
      );
    }
    boostRewardsMultiplierContract = _contract;
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

  function setBoostRewardsPercent(uint256 _perc) external onlyOwner {
    boostRewardsPercent = _perc;
  }

  function setRewardsClaimTimeSeconds(uint256 _seconds) external onlyOwner {
    rewardsClaimTimeSeconds = _seconds;
  }

  function setOklgContract(address cont) external onlyOwner {
    _oklg = IOKLG(cont);
  }

  function getOklgContract() external view returns (address) {
    return address(_oklg);
  }

  function getBoostMultiplier(address wallet) public view returns (uint256) {
    return
      boostRewardsMultiplierContract == address(0)
        ? boostRewardsPercent
        : IMultiplier(boostRewardsMultiplierContract).getMultiplier(wallet);
  }

  function calculateETHRewards(address wallet) public view returns (uint256) {
    uint256 baseRewards = address(this)
      .balance
      .mul(_oklg.balanceOf(wallet))
      .div(
        _oklg.totalSupply().sub(_oklg.balanceOf(deadAddress)) // circulating supply
      );
    uint256 rewardsWithBooster = eligibleForRewardBooster(wallet)
      ? baseRewards.add(baseRewards.mul(getBoostMultiplier(wallet)).div(10**2))
      : baseRewards;
    return
      rewardsWithBooster > address(this).balance
        ? baseRewards
        : rewardsWithBooster;
  }

  function calculateTokenRewards(address wallet, address tokenAddress)
    public
    view
    returns (uint256)
  {
    IERC20 token = IERC20(tokenAddress);
    uint256 contractTokenBalance = token.balanceOf(address(this));
    uint256 baseRewards = contractTokenBalance.mul(_oklg.balanceOf(wallet)).div(
        _oklg.totalSupply().sub(_oklg.balanceOf(deadAddress)) // circulating supply
      );
    uint256 rewardsWithBooster = eligibleForRewardBooster(wallet)
      ? baseRewards.add(baseRewards.mul(getBoostMultiplier(wallet)).div(10**2))
      : baseRewards;
    return
      rewardsWithBooster > contractTokenBalance
        ? baseRewards
        : rewardsWithBooster;
  }

  function canClaimRewards(address user) public view returns (bool) {
    return
      block.timestamp > _rewardsLastClaim[user].add(rewardsClaimTimeSeconds) &&
      block.timestamp >
      _oklg.getLastETHRewardsClaim(user).add(rewardsClaimTimeSeconds);
  }

  function eligibleForRewardBooster(address wallet) public view returns (bool) {
    return
      boostRewardsContract != address(0) &&
      IConditional(boostRewardsContract).passesTest(wallet);
  }

  function resetLastClaim(address _user) external onlyOwner {
    _rewardsLastClaim[_user] = 0;
  }

  function claimETHRewards() external {
    require(
      _oklg.balanceOf(_msgSender()) > 0,
      'You must have a balance to claim ETH rewards'
    );
    require(
      canClaimRewards(_msgSender()),
      'Must wait claim period before claiming rewards'
    );
    _rewardsLastClaim[_msgSender()] = block.timestamp;

    uint256 rewardsSent = calculateETHRewards(_msgSender());
    payable(_msgSender()).call{ value: rewardsSent }('');
    emit SendETHRewards(_msgSender(), rewardsSent);
  }

  function claimTokenRewards(address token) external {
    require(
      _oklg.balanceOf(_msgSender()) > 0,
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

  // to recieve ETH from uniswapV2Router when swaping
  receive() external payable {}
}
