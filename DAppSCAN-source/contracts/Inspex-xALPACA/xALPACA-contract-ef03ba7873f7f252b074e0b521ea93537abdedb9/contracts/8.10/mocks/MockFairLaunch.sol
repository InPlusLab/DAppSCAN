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
*/

pragma solidity 0.8.10;

import "../interfaces/IFairLaunch.sol";
import "../SafeToken.sol";

// FairLaunch is a smart contract for distributing ALPACA by asking user to stake the ERC20-based token.
contract MockFairLaunch is IFairLaunch {
  using SafeToken for address;

  // Info of each pool.
  struct PoolInfo {
    address stakeToken; // Address of Staking token contract.
    uint256 allocPoint; // How many allocation points assigned to this pool. ALPACAs to distribute per block.
    uint256 lastRewardBlock; // Last block number that ALPACAs distribution occurs.
    uint256 accAlpacaPerShare; // Accumulated ALPACAs per share, times 1e12. See below.
    uint256 accAlpacaPerShareTilBonusEnd; // Accumated ALPACAs per share until Bonus End.
  }

  // The Alpaca TOKEN!
  address public alpaca;
  address public proxyToken;
  uint256 public constant DEFAULT_HARVEST_AMOUNT = 10 * 1e18;

  PoolInfo[] public override poolInfo;

  constructor(address _alpaca, address _proxyToken) {
    alpaca = _alpaca;
    proxyToken = _proxyToken;
  }

  function addPool(address _stakeToken) external {
    poolInfo.push(
      PoolInfo({
        stakeToken: _stakeToken,
        allocPoint: 0,
        lastRewardBlock: 0,
        accAlpacaPerShare: 0,
        accAlpacaPerShareTilBonusEnd: 0
      })
    );
  }

  // Deposit Staking tokens to FairLaunchToken for ALPACA allocation.
  function deposit(
    address _for,
    uint256 _pid,
    uint256 _amount
  ) external override {
    SafeToken.safeApprove(proxyToken, _for, _amount);
    proxyToken.safeTransferFrom(_for, address(this), _amount);
    SafeToken.safeApprove(proxyToken, _for, 0);
  }

  function withdrawAll(address _for, uint256 _pid) external override {
    if (proxyToken.myBalance() > 0) {
      SafeToken.safeApprove(proxyToken, _for, proxyToken.myBalance());
      proxyToken.safeTransfer(_for, proxyToken.myBalance());
      SafeToken.safeApprove(proxyToken, _for, 0);
    }
  }

  // Harvest ALPACAs earn from the pool.
  function harvest(uint256 _pid) external override {
    require(DEFAULT_HARVEST_AMOUNT <= alpaca.myBalance(), "wtf not enough alpaca");
    SafeToken.safeApprove(alpaca, msg.sender, DEFAULT_HARVEST_AMOUNT);
    alpaca.safeTransfer(msg.sender, DEFAULT_HARVEST_AMOUNT);
    SafeToken.safeApprove(alpaca, msg.sender, 0);
  }
}
