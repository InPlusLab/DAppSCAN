// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4 <0.9.0;

import './V2DetachedJob.sol';

contract HarvestV2DetachedJob is V2DetachedJob {
  constructor(
    address _baseFeeOracle,
    address _mechanicsRegistry,
    address _yOracle,
    address _v2Keeper,
    uint256 _workCooldown
  )
    V2DetachedJob(_baseFeeOracle, _mechanicsRegistry, _yOracle, _v2Keeper, _workCooldown) // solhint-disable-next-line no-empty-blocks
  {}

  function workable(address _strategy) external view override returns (bool) {
    return _workable(_strategy);
  }

  function _workable(address _strategy) internal view override returns (bool) {
    if (!super._workable(_strategy)) return false;
    return IBaseStrategy(_strategy).harvestTrigger(_getCallCosts(_strategy));
  }

  function _work(address _strategy) internal override {
    lastWorkAt[_strategy] = block.timestamp;
    IV2Keeper(v2Keeper).harvest(_strategy);
  }

  // Keep3r actions
  function work(address _strategy) external override notPaused {
    _workInternal(_strategy);
  }
}
