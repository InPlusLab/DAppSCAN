// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@yearn/contract-utils/contracts/abstract/UtilsReady.sol';
import '@yearn/contract-utils/contracts/interfaces/keep3r/IKeep3rV1.sol';

import '../../interfaces/keep3r/IUniswapV2SlidingOracle.sol';
import '../../interfaces/oracle/IOracleBondedKeeper.sol';

contract OracleBondedKeeper is UtilsReady, IOracleBondedKeeper {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet internal _validJobs;

  address public immutable override keep3r;
  address public immutable override keep3rV1Oracle;

  constructor(address _keep3r, address _keep3rV1Oracle) public UtilsReady() {
    keep3r = _keep3r;
    keep3rV1Oracle = _keep3rV1Oracle;
  }

  // Setters
  function addJobs(address[] calldata _jobs) external override onlyGovernor {
    for (uint256 i; i < _jobs.length; i++) {
      _addJob(_jobs[i]);
    }
  }

  function addJob(address _job) external override onlyGovernor {
    _addJob(_job);
  }

  function _addJob(address _job) internal {
    _validJobs.add(_job);
    emit JobAdded(_job);
  }

  function removeJob(address _job) external override onlyGovernor {
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
  function workable(address _pair) external view override returns (bool) {
    return IUniswapV2SlidingOracle(keep3rV1Oracle).workable(_pair);
  }

  function updatePair(address _pair) external override onlyValidJob returns (bool _updated) {
    return IUniswapV2SlidingOracle(keep3rV1Oracle).updatePair(_pair);
  }

  modifier onlyValidJob() {
    require(_validJobs.contains(msg.sender), 'OracleBondedKeeper::onlyValidJob:msg-sender-not-valid-job');
    _;
  }

  // Governor Keeper Bond
  function bond(address _bonding, uint256 _amount) external override onlyGovernor {
    IKeep3rV1(keep3r).bond(_bonding, _amount);
  }

  function activate(address _bonding) external override onlyGovernor {
    IKeep3rV1(keep3r).activate(_bonding);
  }

  function unbond(address _bonding, uint256 _amount) external override onlyGovernor {
    IKeep3rV1(keep3r).unbond(_bonding, _amount);
  }

  function withdraw(address _bonding) external override onlyGovernor {
    IKeep3rV1(keep3r).withdraw(_bonding);
  }
}
