// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

import '../../proxy-job/Keep3rJob.sol';

contract Keep3rJobMock is Keep3rJob {
  uint256 public timesWorked = 0;
  bool public workableReturn = true;

  constructor(address _keep3rProxyJob, uint256 _maxGasPrice) public Keep3rJob(_keep3rProxyJob) {
    _setMaxGasPrice(_maxGasPrice);
  }

  // Job actions
  function getWorkData() public override returns (bytes memory _workData) {
    return abi.encode(address(this));
  }

  function decodeWorkData(bytes memory _workData) public pure returns (address _vault) {
    return abi.decode(_workData, (address));
  }

  function workable() public override returns (bool) {
    return workableReturn;
  }

  function workable(address _contractAddress) public view returns (bool) {
    return _contractAddress == address(this);
  }

  // Keep3r actions
  function work(bytes memory _workData) external override onlyProxyJob limitGasPrice {
    address _decodedData = decodeWorkData(_workData);
    require(workable(_decodedData), 'Keep3rJobMock::not-workable');
    timesWorked += 1;
  }

  // Mechanics Setters
  function setMaxGasPrice(uint256 _maxGasPrice) external {
    _setMaxGasPrice(_maxGasPrice);
  }

  // Governable
  function acceptGovernor() external override {}

  function governor() external view override returns (address _governor) {
    return msg.sender;
  }

  function isGovernor(address _account) external view override returns (bool _isGovernor) {
    _account; // shh
    return true;
  }

  function pendingGovernor() external view override returns (address _pendingGovernor) {}

  function setPendingGovernor(address _pendingGovernor) external override {}

  // Setter for test
  function setWorkableReturn(bool _workableReturn) external {
    workableReturn = _workableReturn;
  }
}
