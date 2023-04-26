// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import './V2Keep3rJob.sol';

import '@lbertenasco/bonded-stealth-tx/contracts/utils/OnlyStealthRelayer.sol';
import '../../interfaces/jobs/v2/IV2Keep3rStealthJob.sol';

import '../../interfaces/stealth/IStealthRelayer.sol';

abstract contract V2Keep3rStealthJob is V2Keep3rJob, OnlyStealthRelayer, IV2Keep3rStealthJob {
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
    V2Keep3rJob(_mechanicsRegistry, _yOracle, _keep3r, _bond, _minBond, _earned, _age, _onlyEOA, _v2Keeper, _workCooldown)
    OnlyStealthRelayer(_stealthRelayer)
  // solhint-disable-next-line no-empty-blocks
  {

  }

  // Stealth Relayer Setters
  function setStealthRelayer(address _stealthRelayer) external override onlyGovernor {
    _setStealthRelayer(_stealthRelayer);
  }

  // Mechanics keeper bypass
  function forceWork(address _strategy) external override onlyStealthRelayer {
    address _caller = IStealthRelayer(stealthRelayer).caller();
    require(isGovernor(_caller) || isMechanic(_caller), 'V2Keep3rStealthJob::forceWork:invalid-stealth-caller');
    _forceWork(_strategy);
  }

  function forceWorkUnsafe(address _strategy) external override onlyGovernorOrMechanic {
    _forceWork(_strategy);
  }
}
