// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@yearn/contract-utils/contracts/abstract/MachineryReady.sol';

import '../../interfaces/jobs/v2/IV2Keeper.sol';
import '../../interfaces/yearn/IBaseStrategy.sol';

contract V2Keeper is MachineryReady, IV2Keeper {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet internal _validJobs;

  // solhint-disable-next-line no-empty-blocks
  constructor(address _mechanicsRegistry) MachineryReady(_mechanicsRegistry) {}

  // Setters
  function addJobs(address[] calldata _jobs) external override onlyGovernorOrMechanic {
    for (uint256 i; i < _jobs.length; i++) {
      _addJob(_jobs[i]);
    }
  }

  function addJob(address _job) external override onlyGovernorOrMechanic {
    _addJob(_job);
  }

  function _addJob(address _job) internal {
    _validJobs.add(_job);
    emit JobAdded(_job);
  }

  function removeJob(address _job) external override onlyGovernorOrMechanic {
    _validJobs.remove(_job);
    emit JobRemoved(_job);
  }

  // Getters
  function jobs() public view override returns (address[] memory _jobs) {
    _jobs = new address[](_validJobs.length());
    for (uint256 i; i < _validJobs.length(); i++) {
      _jobs[i] = _validJobs.at(i);
    }
  }

  // Jobs functions
  function tend(address _strategy) external override onlyValidJob {
    IBaseStrategy(_strategy).tend();
  }

  function harvest(address _strategy) external override onlyValidJob {
    IBaseStrategy(_strategy).harvest();
  }

  modifier onlyValidJob() {
    require(_validJobs.contains(msg.sender), 'V2Keeper::onlyValidJob:msg-sender-not-valid-job');
    _;
  }
}
