pragma solidity ^0.4.19;

import '../token/ERC20/ERC20Interface.sol';
import '../math/SafeMath.sol';
import './DaicoPool.sol';


contract Voting{
    using SafeMath for uint256;

    address public votingTokenAddr;
    address public poolAddr;
    mapping (uint256 => mapping(address => uint256)) deposits;
    mapping (uint => bool) queued;

    uint256 proposalCostWei = 1 * 10**18;

    uint256 public constant VOTING_PERIOD = 14 days;

    struct Proposal {
        uint256 start_time;
        uint256 end_time;
        Subject subject;
        string reason;
        mapping (bool => uint256) votes; 
        uint256 voter_count;
        bool isFinalized;
        uint256 tapMultiplierRate;
    }

    Proposal[] public proposals;

    enum Subject {
        RaiseTap,
        Destruction
    }

    function Voting (
        address _votingTokenAddr,
        address _poolAddr
    ) public {
        require(_votingTokenAddr != address(0x0));
        votingTokenAddr = _votingTokenAddr;
        poolAddr = _poolAddr;
    }

    function addRaiseTapProposal (
        string _reason,
        uint256 _tapMultiplierRate
    ) external payable returns(uint256) {
        require(!queued[uint(Subject.RaiseTap)]);
        require(100 < _tapMultiplierRate && _tapMultiplierRate <= 200);

        uint256 newID = addProposal(Subject.RaiseTap, _reason);
        proposals[newID].tapMultiplierRate = _tapMultiplierRate;

        queued[uint(Subject.RaiseTap)] = true;
    }

    function addDestructionProposal (string _reason) external payable returns(uint256) {
        require(!queued[uint(Subject.Destruction)]);

        uint256 newID = addProposal(Subject.Destruction, _reason);

        queued[uint(Subject.Destruction)] = true;
    }

    function vote (bool agree, uint256 amount) external {
        require(ERC20Interface(votingTokenAddr).transferFrom(msg.sender, this, amount));
        uint256 pid = this.getCurrentVoting();

        require(proposals[pid].start_time >= block.timestamp);
        require(proposals[pid].end_time < block.timestamp);

        if (deposits[pid][msg.sender] == 0) {
            proposals[pid].voter_count = proposals[pid].voter_count.add(1);
        }

        deposits[pid][msg.sender] = deposits[pid][msg.sender].add(amount);
        proposals[pid].votes[agree] = proposals[pid].votes[agree].add(amount);
    }
    // SWC-113-DoS with Failed Call: L83 - L101
    function finalizeVoting () external {
        uint256 pid = this.getCurrentVoting();
        require(proposals[pid].end_time <= block.timestamp);
        require(!proposals[pid].isFinalized);

        proposals[pid].isFinalized = true;

        if (isPassed(pid)) {
            if (isSubjectRaiseTap(pid)) {
                DaicoPool(poolAddr).raiseTap(proposals[pid].tapMultiplierRate);
                queued[uint(Subject.RaiseTap)] = false;
            } else if (isSubjectDestruction(pid)) {
                DaicoPool(poolAddr).selfDestruction();
                queued[uint(Subject.Destruction)] = false;
            } else {
                revert();
            }
        }
    }

    function returnToken (address account) external returns(bool) {
        uint256 amount = 0;
    
        for (uint256 pid = 0; pid < this.getCurrentVoting(); pid++) {
            amount = amount.add(deposits[pid][account]);
            deposits[pid][account] = 0;
        }

        if(amount <= 0){
           return false;
        }

        return ERC20Interface(votingTokenAddr).transfer(msg.sender, amount);
    }

    function returnTokenMulti (address[] accounts) external {
        for(uint256 i = 0; i < accounts.length; i++){
            this.returnToken(accounts[i]);
        }
    }

    function getCurrentVoting () public constant returns(uint256) {
        for (uint256 i = 0; i < proposals.length; i++) {
            if (!proposals[i].isFinalized) {
                return i;
            }
        }
        revert();
    }

    // SWC-113-DoS with Failed Call: L134 - L140, 
    function isPassed (uint256 pid) public constant returns(bool) {
        require(proposals[pid].isFinalized);
        uint256 ayes = getAyes(pid);
        uint256 nays = getNays(pid);
        uint256 absent = ERC20Interface(votingTokenAddr).totalSupply().sub(ayes).sub(nays);
        return (ayes.sub(nays).add(absent.div(6)) > 0);
    }

    function isStarted (uint256 pid) public constant returns(bool) {
        if (pid > getCurrentVoting()) {
            return false;
        } else if (block.timestamp >= proposals[pid].start_time) {
            return true;
        }
        return false;
    }

    function isEnded (uint256 pid) public constant returns(bool) {
        if (pid > getCurrentVoting()) {
            return false;
        } else if (block.timestamp >= proposals[pid].end_time) {
            return true;
        }
        return false;
    }

    function getReason (uint256 pid) external constant returns(string) {
        require(pid <= getCurrentVoting());
        return proposals[pid].reason;
    }

    function isSubjectRaiseTap (uint256 pid) public constant returns(bool) {
        require(pid <= getCurrentVoting());
        return proposals[pid].subject == Subject.RaiseTap;
    }

    function isSubjectDestruction (uint256 pid) public constant returns(bool) {
        require(pid <= getCurrentVoting());
        return proposals[pid].subject == Subject.Destruction;
    }

    function getVoterCount (uint256 pid) external constant returns(uint256) {
        require(pid <= getCurrentVoting());
        return proposals[pid].voter_count;
    }

    function getAyes (uint256 pid) public constant returns(uint256) {
        require(pid <= getCurrentVoting());
        require(proposals[pid].isFinalized);
        return proposals[pid].votes[true];
    }

    function getNays (uint256 pid) public constant returns(uint256) {
        require(pid <= getCurrentVoting());
        require(proposals[pid].isFinalized);
        return proposals[pid].votes[false];
    }

    function addProposal (Subject _subject, string _reason) internal returns(uint256) {
        require(msg.value == proposalCostWei);
        poolAddr.transfer(msg.value);

        Proposal memory proposal;
        proposal.subject = _subject;
        proposal.reason = _reason;

        uint256 newID = proposals.length;
        proposals[newID] = proposal;
        return newID;
    }
}
