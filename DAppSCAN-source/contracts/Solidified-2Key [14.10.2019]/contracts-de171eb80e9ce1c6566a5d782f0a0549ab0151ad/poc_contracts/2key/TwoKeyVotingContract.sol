// Voting.sol
// Enigma, 2018
// Implement secret voting.

pragma solidity ^0.4.24;

import "./Enigma.sol"; // ../../../enigmampc/secret-contracts/contracts/

contract TwoKeyVotingContract {
  using SafeMath for uint;

  /* EVENTS */
  event voteCasted(address voter, bytes vote);
  event pollCreated(address creator, uint quorumPercentage, string description, uint votingLength);
  event pollStatusUpdate(bool status);

  /* Determine the current state of a poll */
  enum PollStatus { IN_PROGRESS, TALLY, PASSED, REJECTED }

  /* POLL */
  struct Poll {
    address creator;
    PollStatus status;
    uint quorumPercentage;
    uint yeaVotes;
    uint nayVotes;
    string description;
    address[] voters;
    uint expirationTime;
    mapping(address => Voter) voterInfo;
  }

  /* VOTER */
  struct Voter {
    bool hasVoted;
    bytes vote;
  }

  /* STATE VARIABLES */
  Poll public polls;
  Enigma public enigma;

  /* CONSTRUCTOR */
  constructor(address _token, address _enigma) public {
//    require(_token != 0 && address(token) == 0);
    require(_enigma != 0 && address(enigma) == 0);
    enigma = Enigma(_enigma);
  }

  /* POLL OPERATIONS */

  /*
   * Creates a new poll with a specified quorum percentage.
   */
  function createPoll(uint _quorumPct, string _description, uint _voteLength) public {
    require(_quorumPct <= 100, "Quorum Percentage must be less than or equal to 100%");
    require(_voteLength > 0, "The voting period cannot be 0.");

    polls.creator = msg.sender;
    polls.status = PollStatus.IN_PROGRESS;
    polls.quorumPercentage = _quorumPct;
    polls.expirationTime = now + _voteLength * 1 seconds;
    polls.description = _description;

    emit pollCreated(msg.sender, _quorumPct, _description, _voteLength);
  }

  /*
   * Ends a poll. Only the creator of a given poll can end that poll.
   */
  function endPoll() external  {
    require(msg.sender == polls.creator, "User is not the creator of the poll.");
    require(polls.status == PollStatus.IN_PROGRESS, "Vote is not in progress.");
    require(now >= getPollExpirationTime(), "Voting period has not expired");
    polls.status = PollStatus.TALLY;
  }

  /*
   * The callback function. Checks if a poll was passed given the quorum percentage and vote distribution.
   * NOTE: Only the Enigma contract can call this function.
   */
  function updatePollStatus(uint _yeaVotes, uint _nayVotes) public onlyEnigma() {
    require(getPollStatus() == PollStatus.TALLY, "Poll has not expired yet.");
    polls.yeaVotes = _yeaVotes;
    polls.nayVotes = _nayVotes;

    bool pollStatus = (polls.yeaVotes.mul(100)) > polls.quorumPercentage.mul(polls.yeaVotes.add(polls.nayVotes));
    if (pollStatus) {
      polls.status = PollStatus.PASSED;
    }
    else {
      polls.status = PollStatus.REJECTED;
    }

    emit pollStatusUpdate(pollStatus);
  }

  /*
   * Gets the status of a poll.
   */
  function getPollStatus() public view returns (PollStatus) {
    return polls.status;
  }

  /*
   * Gets the expiration date of a poll.
   */
  function getPollExpirationTime() public view returns (uint) {
    return polls.expirationTime;
  }

  /*
   * Gets a voter's encrypted vote for a given expired poll.
   */
  function getPollInfoForVoter(address _voter) public view returns (bytes) {
    require(getPollStatus() != PollStatus.IN_PROGRESS);
    require(userHasVoted(_voter));
    return polls.voterInfo[_voter].vote;
  }

  /*
   * Gets all the voters of a poll.
   */
  function getVotersForPoll() public view returns (address[]) {
    require(getPollStatus() != PollStatus.IN_PROGRESS);
    return polls.voters;
  }

  /*
   * Modifier that checks that the contract caller is the Enigma contract.
   */
  modifier onlyEnigma() {
    require(msg.sender == address(enigma));
    _;
  }

  /* VOTE OPERATIONS */

  /*
   * Casts a vote for a given poll.
   */
  function castVote(bytes _encryptedVote) external {
    require(getPollStatus() == PollStatus.IN_PROGRESS, "Poll has expired.");
    require(!userHasVoted(msg.sender), "User has already voted.");
    require(getPollExpirationTime() > now);

    polls.voterInfo[msg.sender] = Voter({
      hasVoted: true,
      vote: _encryptedVote
      });

    polls.voters.push(msg.sender);

    emit voteCasted(msg.sender, _encryptedVote);
  }

  /*
   * The callable function that is computed by the SGX node. Tallies votes.
   */
  function countVotes(uint[] _votes, uint weight) public pure returns (uint, uint) {
    uint yeaVotes;
    uint nayVotes;
    for (uint i = 0; i < _votes.length; i++) {
      if (_votes[i] == 0) nayVotes += weight;
      else if (_votes[i] == 1) yeaVotes += weight;
    }
    return (yeaVotes, nayVotes);
  }

  /*
   * Checks if a user has voted for a specific poll.
   */
  function userHasVoted(address _user) public view returns (bool) {
    return (polls.voterInfo[_user].hasVoted);
  }

}
