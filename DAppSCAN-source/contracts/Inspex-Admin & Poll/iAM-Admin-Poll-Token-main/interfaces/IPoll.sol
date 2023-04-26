// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

interface IPoll {
  struct VoteReceive {
    uint256 vote;
    uint256 amount;
  }

  struct Proposal {
    string desc;
    uint256 voteAmount;
    bool valid;
  }

  event Initialize(
    uint256 _timeStart,
    uint256 _timeEnd,
    uint256 _min,
    uint256 _max,
    bool indexed _burnType,
    bool indexed _multiType,
    string[] _proposals
  );
  event Voted(address indexed _voter, uint256 _amount, uint256 indexed _proposal);
  event AddProposal(string[] _proposals);
  event Transfer(address indexed _to, uint256 _amount);

  function voteToken() external view returns (address);

  function factory() external view returns (address);

  function question() external view returns (string memory);

  function desc() external view returns (string memory);

  function startBlock() external view returns (uint256);

  function endBlock() external view returns (uint256);

  function emergencyClose() external view returns (bool);

  function init() external view returns (bool);

  function minimumToken() external view returns (uint256);

  function maximumToken() external view returns (uint256);

  function burnType() external view returns (bool);

  function multiType() external view returns (bool);

  function highestVotedIndex() external view returns (uint256);

  function highestVotedAmount() external view returns (uint256);

  function voterReceive(address) external view returns (uint256);

  function voterCount() external view returns (uint256);

  function editPollVoteTime(uint256 _startBlock, uint256 _endBlock) external;

  function directClosePoll() external;

  function isFinished() external view returns (bool);

  function burnToken() external returns (bool);

  function getProposalList() external view returns (Proposal[] memory);

  function addProposalNames(string[] memory _proposalNames) external returns (bool);

  function editProposalDesc(uint256 _index, string memory _desc) external returns (bool);

  function withdrawFor(address _toaddress) external returns (bool);

  function vote(uint256 _proposal, uint256 _amount) external returns (bool);
}
