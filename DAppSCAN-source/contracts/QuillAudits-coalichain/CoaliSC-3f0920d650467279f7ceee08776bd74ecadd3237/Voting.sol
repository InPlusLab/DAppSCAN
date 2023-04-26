pragma solidity ^0.4.21;

import "Main.sol";
import "CoalichainToken.sol";
import "Types.sol";

contract Voting {
  using SafeMath for uint256;

  enum Stages {
      UNREGISTERED,
      REGISTERED,
      VOTED
  }

  struct Voter {
    address voterAddress; // The address of the voter
    Stages state;
    address votedFor;
  }

  mapping (address => Voter) private voterInfo;
  address private owner;
  Main private mainContract;
  address private mainAddress;
  mapping (address => uint256) public votesReceived;
  address[] public candidateList;
  address private coaliWallet;
  uint256 public _balloutDBId = 0;
  
  event Voted(address voterAddress, address candidate, uint256 newVotesReceived, uint256 correlationID);
  event Unvoted(address voterAddress, address candidate, uint256 newVotesReceived, uint256 correlationID);
  event voterApproved(address voterAddress);

  constructor(
      address _owner,
      address[] candidateNames,
      address _coaliWallet,
	  uint256 balloutDBId)
      public {

      candidateList = candidateNames;
      coaliWallet = _coaliWallet;
      mainContract = Main(msg.sender); // TODO: check if the msg.sender is secure!
      mainAddress = msg.sender;
      owner = _owner;
	  _balloutDBId = balloutDBId;
      voterInfo[_owner].state = Stages.VOTED;
  }



  function getCandidatesList() view public returns (address[], uint256[]){
     uint256[] memory votes = new uint256[](candidateList.length);
     for (uint index = 0; index < candidateList.length; index++) {
       votes[index] = votesReceived[candidateList[index]];
     }
     return (candidateList, votes);
  }

  function getMyVoterState() public view returns (uint8) {
    return (uint8(voterInfo[msg.sender].state) + 1);
  }


  function totalVotesFor(address candidate) view public returns (uint256) {
      require(validCandidate(candidate));
      return votesReceived[candidate];
  }

  function getBalloutDBID() view public returns (uint256){
	return _balloutDBId;
  }


  function voteForCandidate(address candidate, uint256 correlationID) public returns (bool) {

      require(validCandidate(candidate));

      
	if(voterInfo[msg.sender].votedFor != candidate) {
		   voterInfo[msg.sender].votedFor = candidate;
		   votesReceived[candidate] = votesReceived[candidate].add(1);
		   emit Voted(msg.sender, candidate, votesReceived[candidate], correlationID);
		   
		   mainContract.payForService(msg.sender, 1000000);

	  }

	  return true;
    }


    function changeVote(address newCandidate, uint256 correlationID) public returns (bool) {
        require(msg.sender != owner);
        address oldCandidate = voterInfo[msg.sender].votedFor;
        require(validCandidate(newCandidate));
        require(validCandidate(oldCandidate));
   

        votesReceived[oldCandidate] = votesReceived[oldCandidate].sub(1);
        votesReceived[newCandidate] = votesReceived[newCandidate].add(1);
        voterInfo[msg.sender].votedFor = newCandidate;
        emit Unvoted(msg.sender, oldCandidate, votesReceived[oldCandidate], correlationID);
        emit Voted(msg.sender, newCandidate, votesReceived[newCandidate], correlationID);

		if (mainContract.chargeZuz()) {
            mainContract.payForService(msg.sender, uint256(Types.Service.CHANGE_VOTE));
        }
		
			return true;
    }


    function unvoteForCandidate(uint256 correlationID) public returns (bool) {
        require(msg.sender != owner);
        address candidate = voterInfo[msg.sender].votedFor;
  
        votesReceived[candidate] = votesReceived[candidate].sub(1);
        voterInfo[msg.sender].state = Stages(uint(voterInfo[msg.sender].state).sub(1));
        emit Unvoted(msg.sender, candidate, votesReceived[candidate], correlationID);

       if (mainContract.chargeZuz()) {
            mainContract.payForService(msg.sender, uint256(Types.Service.UNVOTE));
        }
		
		return true;
    }

    function validCandidate(address candidate) view public returns (bool) {
        for(uint i = 0; i < candidateList.length; i++) {
            if (candidateList[i] == candidate) {
                return true;
              }
          }

        return false;
    }
}
