// SPDX-License-Identifier: MIT

pragma solidity >=0.6.8;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@yearn/contract-utils/contracts/abstract/UtilsReady.sol';

import '../interfaces/internal-jobs/IStealthVault.sol';

/*
 * StealthVault
 */
contract StealthVault is UtilsReady, IStealthVault {
  using SafeMath for uint256;

  // report
  uint256 public override requiredReportBond = 1 ether / 10; // 0.1 ether
  mapping(bytes32 => address) public override hashReportedBy;
  mapping(bytes32 => uint256) public override hashReportedBond;
  // penalty
  mapping(bytes32 => uint256) public override hashPenaltyAmount;
  mapping(bytes32 => uint256) public override hashPenaltyCooldown;
  mapping(bytes32 => address) public override hashPenaltyKeeper;

  mapping(address => mapping(address => bool)) internal _keeperStealthJobs;

  function keeperStealthJob(address _keeper, address _job) external view override returns (bool _enabled) {
    return _keeperStealthJobs[_keeper][_job];
  }

  uint256 public override totalBonded;
  mapping(address => uint256) public override bonded;

  // Penalty lock for 1 week to make sure it was not an uncle block. (find a way to make this not a stress on governor)
  uint256 public override penaltyReviewPeriod = 1 weeks;

  constructor() public UtilsReady() {}

  function isStealthVault() external pure override returns (bool) {
    return true;
  }

  // Governor
  function setPenaltyReviewPeriod(uint256 _penaltyReviewPeriod) external override onlyGovernor {
    penaltyReviewPeriod = _penaltyReviewPeriod;
  }

  function setRequiredReportBond(uint256 _requiredReportBond) external override onlyGovernor {
    requiredReportBond = _requiredReportBond;
  }

  function transferGovernorBond(address _keeper, uint256 _amount) external override onlyGovernor {
    bonded[governor] = bonded[governor].sub(_amount);
    bonded[_keeper] = bonded[_keeper].add(_amount);
  }

  // Bonds
  function bond() external payable override {
    _addBond(msg.sender, msg.value);
  }

  function _addBond(address _keeper, uint256 _amount) internal {
    require(_amount > 0, 'StealthVault::addBond:amount-should-be-greater-than-zero');
    bonded[_keeper] = bonded[_keeper].add(_amount);
    totalBonded = totalBonded.add(_amount);
    emit Bonded(_keeper, _amount, bonded[_keeper]);
  }

  function unbondAll() external override {
    unbond(bonded[msg.sender]);
  }

  function unbond(uint256 _amount) public override {
    require(_amount > 0, 'StealthVault::unbond:amount-should-be-greater-than-zero');

    bonded[msg.sender] = bonded[msg.sender].sub(_amount);
    totalBonded = totalBonded.sub(_amount);

    payable(msg.sender).transfer(_amount);
    emit Unbonded(msg.sender, _amount, bonded[msg.sender]);
  }

  function _lockBond(
    bytes32 _hash,
    address _keeper,
    uint256 _amount
  ) internal {
    bonded[_keeper] = bonded[_keeper].sub(_amount);
    hashPenaltyCooldown[_hash] = block.timestamp.add(penaltyReviewPeriod);
    hashPenaltyKeeper[_hash] = _keeper;
    hashPenaltyAmount[_hash] = _amount;
  }

  // Hash
  function validateHash(
    address _keeper,
    bytes32 _hash,
    uint256 _penalty
  ) external override returns (bool) {
    // keeper is required to be an EOA to avoid on-chain hash generation to bypass penalty
    require(_keeper == tx.origin, 'StealthVault::validateHash:keeper-should-be-EOA');
    require(_keeperStealthJobs[_keeper][msg.sender], 'StealthVault::validateHash:keeper-job-not-enabled');
    require(bonded[_keeper] >= _penalty, 'StealthVault::validateHash:bond-less-than-penalty');

    address reportedBy = hashReportedBy[_hash];
    if (reportedBy != address(0)) {
      // User reported this TX as public, locking penalty away
      _lockBond(_hash, _keeper, _penalty);

      emit BondTaken(_hash, _keeper, _penalty, reportedBy);
      // invalid: has was reported
      return false;
    }

    emit ValidatedHash(_hash, _keeper, _penalty);
    // valid: has was not reported
    return true;
  }

  // TODO ?
  // function softReportHash(bytes32 _hash) external override {
  // }

  function reportHash(bytes32 _hash) external override {
    require(bonded[msg.sender] >= requiredReportBond, 'StealthVault::reportHash:bond-less-than-required-report-bond');
    require(hashReportedBy[_hash] == address(0), 'StealthVault::reportHash:hash-already-reported');

    hashReportedBy[_hash] = msg.sender;
    hashReportedBond[_hash] = requiredReportBond;

    bonded[msg.sender] = bonded[msg.sender].sub(requiredReportBond);

    emit ReportedHash(_hash, msg.sender, requiredReportBond);
  }

  // Penalty
  function claimPenalty(bytes32 _hash) external override {
    require(hashPenaltyCooldown[_hash] >= block.timestamp, 'StealthVault::claimPenalty:hash-penalty-cooldown');
    address reportedBy = hashReportedBy[_hash];
    address keeper = hashPenaltyKeeper[_hash];
    uint256 penaltyAmount = hashPenaltyAmount[_hash];
    uint256 reportAmount = hashReportedBond[_hash];

    _deleteHashData(_hash);

    bonded[reportedBy] = bonded[reportedBy].add(penaltyAmount.add(reportAmount));
    emit ClaimedPenalty(_hash, keeper, reportedBy, penaltyAmount, reportAmount);
  }

  function invalidatePenalty(bytes32 _hash) external override onlyGovernor {
    require(hashPenaltyCooldown[_hash] < block.timestamp, 'StealthVault::invalidatePenalty:hash-penalty-cooldown-expired');
    uint256 reportAmount = hashReportedBond[_hash];

    _deleteHashData(_hash);

    bonded[governor] = bonded[governor].add(reportAmount);
    emit InvalidatedPenalty(_hash, reportAmount);
  }

  function _deleteHashData(bytes32 _hash) internal {
    delete hashReportedBy[_hash];
    delete hashReportedBond[_hash];
    delete hashPenaltyAmount[_hash];
    delete hashPenaltyCooldown[_hash];
    delete hashPenaltyKeeper[_hash];
  }

  // Jobs
  function enableStealthJob(address _job) external override {
    _setKeeperJob(_job, true);
  }

  function enableStealthJobs(address[] calldata _jobs) external override {
    for (uint256 i = 0; i < _jobs.length; i++) {
      _setKeeperJob(_jobs[i], true);
    }
  }

  function disableStealthJob(address _job) external override {
    _setKeeperJob(_job, false);
  }

  function disableStealthJobs(address[] calldata _jobs) external override {
    for (uint256 i = 0; i < _jobs.length; i++) {
      _setKeeperJob(_jobs[i], false);
    }
  }

  function _setKeeperJob(address _job, bool _enabled) internal {
    _keeperStealthJobs[msg.sender][_job] = _enabled;
  }
}
