// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.6;
pragma abicoder v2;

import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';

import {IVotingPowerStrategy} from '../../interfaces/governance/IVotingPowerStrategy.sol';
import {IKyberGovernance} from '../../interfaces/governance/IKyberGovernance.sol';
import {IKyberStaking} from '../../interfaces/staking/IKyberStaking.sol';
import {EpochUtils} from '../../misc/EpochUtils.sol';

/**
 * @title Voting Power Strategy contract based on epoch mechanism
 * @dev Smart contract containing logic to measure users' relative power to vote.
 **/
contract EpochVotingPowerStrategy is IVotingPowerStrategy, EpochUtils {
  using SafeMath for uint256;

  uint256 public constant MAX_PROPOSAL_PER_EPOCH = 10;
  IKyberStaking public immutable staking;
  IKyberGovernance public immutable governance;

  mapping(uint256 => uint256[]) internal epochProposals;

  /**
   * @dev Constructor, register tokens used for Voting and Proposition Powers.
   * @param _governance The address of governance contract.
   * @param _staking The address of the knc staking contract.
   **/
  constructor(IKyberGovernance _governance, IKyberStaking _staking)
    EpochUtils(_staking.epochPeriodInSeconds(), _staking.firstEpochStartTime())
  {
    staking = _staking;
    governance = _governance;
  }

  modifier onlyStaking() {
    require(msg.sender == address(staking), 'only staking');
    _;
  }

  modifier onlyGovernance() {
    require(msg.sender == address(governance), 'only governance');
    _;
  }

  /**
   * @dev stores proposalIds per epoch mapping, so when user withdraws,
   * voting power strategy is aware of which proposals are affected
   */
  function handleProposalCreation(
    uint256 proposalId,
    uint256 startTime,
    uint256 /*endTime*/
  ) external override onlyGovernance {
    uint256 epoch = getEpochNumber(startTime);

    epochProposals[epoch].push(proposalId);
  }

  /**
   * @dev remove proposalId from proposalIds per epoch mapping, so when user withdraws,
   * voting power strategy is aware of which proposals are affected
   */
//  SWC-126-Insufficient Gas Griefing: L66-79
  function handleProposalCancellation(uint256 proposalId) external override onlyGovernance {
    IKyberGovernance.ProposalWithoutVote memory proposal = governance.getProposalById(proposalId);
    uint256 epoch = getEpochNumber(proposal.startTime);

    uint256[] storage proposalIds = epochProposals[epoch];
    for (uint256 i = 0; i < proposalIds.length; i++) {
      if (proposalIds[i] == proposalId) {
        // remove this proposalId out of list
        proposalIds[i] = proposalIds[proposalIds.length - 1];
        proposalIds.pop();
        break;
      }
    }
  }

  /**
   * @dev assume that governance check start and end time
   * @dev call to init data if needed, and return voter's voting power
   * @dev proposalId, choice: unused param for future usage
   */
  function handleVote(
    address voter,
    uint256, /*proposalId*/
    uint256 /*choice*/
  ) external override onlyGovernance returns (uint256 votingPower) {
    (uint256 stake, uint256 dStake, address representative) = staking
      .initAndReturnStakerDataForCurrentEpoch(voter);
    return representative == voter ? stake.add(dStake) : dStake;
  }

  /**
   * @dev handle user withdraw from staking contract
   * @dev notice for governance that voting power for proposalIds in current epoch is changed
   */
  //  SWC-128-DoS With Block Gas Limit: L100-112
  function handleWithdrawal(
    address user,
    uint256 /*reduceAmount*/
  ) external override onlyStaking {
    uint256 currentEpoch = getCurrentEpochNumber();
    (uint256 stake, uint256 dStake, address representative) = staking.getStakerData(
      user,
      currentEpoch
    );
    uint256 votingPower = representative == user ? stake.add(dStake) : dStake;
    governance.handleVotingPowerChanged(user, votingPower, epochProposals[currentEpoch]);
  }

  /**
   * @dev call to get voter's voting power given timestamp
   * @dev only for reading purpose. when submitVote, should call handleVote instead
   */
  function getVotingPower(address voter, uint256 timestamp)
    external
    override
    view
    returns (uint256 votingPower)
  {
    uint256 currentEpoch = getEpochNumber(timestamp);
    (uint256 stake, uint256 dStake, address representative) = staking.getStakerData(
      voter,
      currentEpoch
    );
    votingPower = representative == voter ? stake.add(dStake) : dStake;
  }

  /**
   * @dev validate that a proposal is suitable for epoch mechanism
   */
  function validateProposalCreation(uint256 startTime, uint256 endTime)
    external
    override
    view
    returns (bool)
  {
    /// start in the past
    if (startTime < block.timestamp) {
      return false;
    }
    uint256 startEpoch = getEpochNumber(startTime);
    /// proposal must start and end within an epoch
    if (startEpoch != getEpochNumber(endTime)) {
      return false;
    }
    /// proposal must be current or next epoch
    if (startEpoch > getCurrentEpochNumber().add(1)) {
      return false;
    }
    /// too many proposals
    if (epochProposals[startEpoch].length >= MAX_PROPOSAL_PER_EPOCH) {
      return false;
    }
    return true;
  }

  function getMaxVotingPower() external override view returns (uint256) {
    return staking.kncToken().totalSupply();
  }

  function getListProposalIds(uint256 epoch) external view returns (uint256[] memory proposalIds) {
    return epochProposals[epoch];
  }
}
