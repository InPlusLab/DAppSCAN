// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import './V2QueueKeep3rStealthJob.sol';

contract HarvestV2QueueKeep3rStealthJob is V2QueueKeep3rStealthJob {
  constructor(
    address _mechanicsRegistry,
    address _stealthRelayer,
    address _yOracle,
    address _keep3r,
    address _bond,
    uint256 _minBond,
    uint256 _earned,
    uint256 _age,
    bool _onlyEOA,
    address _v2Keeper,
    uint256 _workCooldown
  )
    V2QueueKeep3rStealthJob(
      _mechanicsRegistry,
      _stealthRelayer,
      _yOracle, /*TODO:_yOracle*/
      _keep3r,
      _bond,
      _minBond,
      _earned,
      _age,
      _onlyEOA,
      _v2Keeper,
      _workCooldown
    )
  // solhint-disable-next-line no-empty-blocks
  {

  }

  function workable(address _strategy) external view override returns (bool) {
    return _workable(_strategy);
  }

  function _workable(address _strategy) internal view override returns (bool) {
    return super._workable(_strategy);
  }

  function _strategyTrigger(address _strategy, uint256 _amount) internal view override returns (bool) {
    if (_amount == 0) return true; // Force harvest on amount 0
    return IBaseStrategy(_strategy).harvestTrigger(_amount);
  }

  function _work(address _strategy) internal override {
    IV2Keeper(v2Keeper).harvest(_strategy);
  }

  // Keep3r actions
  function work(address _strategy) external override notPaused onlyStealthRelayer returns (uint256 _credits) {
    address _keeper = IStealthRelayer(stealthRelayer).caller();
    _isKeeper(_keeper);
    _credits = _workInternal(_strategy);
    _paysKeeperAmount(_keeper, _credits);
  }
}
