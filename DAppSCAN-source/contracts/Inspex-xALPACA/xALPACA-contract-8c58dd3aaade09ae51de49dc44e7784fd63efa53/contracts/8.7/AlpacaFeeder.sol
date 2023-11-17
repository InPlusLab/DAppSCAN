// SPDX-License-Identifier: MIT
/**
  ∩~~~~∩ 
  ξ ･×･ ξ 
  ξ　~　ξ 
  ξ　　 ξ 
  ξ　　 “~～~～〇 
  ξ　　　　　　 ξ 
  ξ ξ ξ~～~ξ ξ ξ 
　 ξ_ξξ_ξ　ξ_ξξ_ξ
Alpaca Fin Corporation
**/

pragma solidity 0.8.7;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IBEP20.sol";
import "./interfaces/IFairLaunch.sol";
import "./interfaces/IGrassHouse.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IProxyToken.sol";

import "./SafeToken.sol";

/// @title AlpacaFeeder
contract AlpacaFeeder is IVault, Initializable, OwnableUpgradeable {
  /// @notice Libraries
  using SafeToken for address;

  /// @notice Events
  event LogFeedGrassHouse(uint256 _feedAmount);
  event LogFairLaunchDeposit();
  event LogFairLaunchWithdraw();
  event LogFairLaunchHarvest(address _caller, uint256 _harvestAmount);

  /// @notice State
  IFairLaunch public fairLaunch;
  IGrassHouse public grassHouse;
  uint256 public fairLaunchPoolId;

  /// @notice Attributes for AlcapaFeeder
  /// token - address of the token to be deposited in this contract
  /// proxyToken - just a simple ERC20 token for staking with FairLaunch
  address public override token;
  address public proxyToken;

  function initialize(
    address _token,
    address _proxyToken,
    address _fairLaunchAddress,
    uint256 _fairLaunchPoolId,
    address _grasshouseAddress
  ) public initializer {
    OwnableUpgradeable.__Ownable_init();

    token = _token;
    proxyToken = _proxyToken;
    fairLaunchPoolId = _fairLaunchPoolId;
    fairLaunch = IFairLaunch(_fairLaunchAddress);
    grassHouse = IGrassHouse(_grasshouseAddress);
    
    (address _stakeToken, , , ,) = fairLaunch.poolInfo(fairLaunchPoolId);
    
    require(_stakeToken == _proxyToken, "!same stakeToken");
    require(grassHouse.rewardToken() == _token, "!same rewardToken");

    proxyToken.safeApprove(_fairLaunchAddress, type(uint256).max);
  }

  /// @notice Deposit token to FairLaunch
  function fairLaunchDeposit() external onlyOwner {
    require(IBEP20(proxyToken).balanceOf(address(fairLaunch)) == 0, "already deposit");
    IProxyToken(proxyToken).mint(address(this), 1e18);
    fairLaunch.deposit(address(this), fairLaunchPoolId, 1e18);
    emit LogFairLaunchDeposit();
  }

  /// @notice Withdraw all staked token from FairLaunch
  function fairLaunchWithdraw() external onlyOwner {
    fairLaunch.withdrawAll(address(this), fairLaunchPoolId);
    IProxyToken(proxyToken).burn(address(this), proxyToken.myBalance());
    emit LogFairLaunchWithdraw();
  }

  /// @notice Receive reward from FairLaunch
  function fairLaunchHarvest() external {
    _fairLaunchHarvest();
  }

  /// @notice Receive reward from FairLaunch
  function _fairLaunchHarvest() internal {
    uint256 _before = token.myBalance();
    (bool _success, ) = address(fairLaunch).call(abi.encodeWithSelector(0xddc63262, fairLaunchPoolId));
    if (_success) emit LogFairLaunchHarvest(address(this), token.myBalance() - _before);
  }

  /// @notice Harvest reward from FairLaunch and Feed token to a GrassHouse
  function feedGrassHouse() external {
    _fairLaunchHarvest();
    uint256 _feedAmount = token.myBalance();
    token.safeApprove(address(grassHouse), _feedAmount);
    grassHouse.feed(_feedAmount);
    emit LogFeedGrassHouse(_feedAmount);
  }
}
