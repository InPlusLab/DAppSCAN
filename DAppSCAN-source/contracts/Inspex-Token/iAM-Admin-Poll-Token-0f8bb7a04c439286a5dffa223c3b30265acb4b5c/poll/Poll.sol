// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '../interfaces/IERC20Burnable.sol';
import '../access/Adminnable.sol';

contract Poll is Adminnable, ReentrancyGuard {
  IERC20Burnable public voteToken;
  address public factory;
  string public question;
  string public name;
  string public desc; // string | ipfs url

  uint256 public startBlock; // start block
  uint256 public endBlock; // end block
  bool public emergencyClose; // emergency close poll
  bool public init;

  uint256 public minimumToken;
  uint256 public maximumToken;
  bool public burnType;
  bool public multiType;

  uint256 public highestVotedIndex;
  uint256 public highestVotedAmount;

  mapping(address => VoteReceive[]) public voterReceive;
  mapping(address => uint256) public lockAmountOf;
  uint256 public voterCount;

  Proposal[] public proposals;

  struct VoteReceive {
    uint256 vote; // index of the voted proposal
    uint256 amount;
  }

  struct Proposal {
    string desc;
    uint256 voteAmount;
    bool valid;
  }

  modifier onlyVoteTime() {
    require(init == true, 'poll: poll is not ready!');
    require(block.number > startBlock, 'poll: not in vote time!');
    require(block.number < endBlock, 'poll: poll is finished!');
    require(!emergencyClose, 'poll: poll is close!');
    _;
  }

  modifier onlyBeforeStart() {
    require(block.number < startBlock, 'poll: poll is started!');
    _;
  }

  modifier onlyFinished() {
    require(block.number > endBlock || emergencyClose, 'poll is not finished!');
    _;
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
  event Proposals(string[] _proposals);
  event Transfer(address indexed _to, uint256 _amount);

  constructor(
    IAdminManage _admin,
    IERC20Burnable _voteToken,
    string memory _question,
    string memory _desc,
    string memory _name
  ) Adminnable(_admin) {
    factory = msg.sender;
    voteToken = _voteToken;
    question = _question;
    desc = _desc;
    name = _name;
  }

  function initialize(
    uint256 _startBlock,
    uint256 _endBlock,
    uint256 _minimumToken,
    uint256 _maximumToken,
    bool _burnType,
    bool _multiType,
    string[] memory _proposals
  ) public {
    require(msg.sender == factory, 'Poll [initialize]: only factory can init poll.');
    require(init == false, 'Poll [initialize]: you can init Poll only 1 time.');
    require(_endBlock > _startBlock, 'Poll [initialize]: endBlock should more then startBlock.');

    init = true;
    startBlock = _startBlock;
    endBlock = _endBlock;
    minimumToken = _minimumToken;
    maximumToken = _maximumToken;
    burnType = _burnType;
    multiType = _multiType;

    // initital genesis at index 0
    proposals.push(Proposal({desc: 'Genesis', voteAmount: 0, valid: true}));
    _addProposals(_proposals);

    emit Initialize(startBlock, endBlock, minimumToken, maximumToken, burnType, multiType, _proposals);
  }

  function editPollVoteTime(uint256 _startBlock, uint256 _endBlock) external onlyAdmin onlyBeforeStart {
    require(endBlock > _startBlock, 'Poll [editPollVoteTime]: endBlock should more then startBlock.');

    startBlock = _startBlock;
    endBlock = _endBlock;
  }

  function directClosePoll() external onlyAdmin {
    emergencyClose = true;
  }

  function isFinished() public view returns (bool) {
    return init && (block.number > endBlock || emergencyClose);
  }

  function burnToken() external onlyAdmin onlyFinished returns (bool) {
    require(burnType, 'Poll [burnToken]: require Poll of burn type.');

    voteToken.burn(voteToken.balanceOf(address(this)));

    return true;
  }

  function getProposalList() external view returns (Proposal[] memory) {
    return proposals;
  }

  function getVoter(address _voter) external view returns (VoteReceive[] memory) {
    return voterReceive[_voter];
  }

  function addProposalNames(string[] memory _proposalNames) public onlyAdmin onlyBeforeStart returns (bool) {
    _addProposals(_proposalNames);
    return true;
  }

  function editProposalDesc(uint256 _index, string memory _desc) public onlyAdmin onlyBeforeStart returns (bool) {
    require(proposals[_index].valid, 'Poll [editProposalDesc]: editProposal is invalid.');
    proposals[_index].desc = _desc;

    return true;
  }

  function withdrawFor(address _toaddress) external onlyFinished nonReentrant returns (bool) {
    // when emergency close poll is call by admin voter can withdown thier token at any time

    if (burnType == false) {
      _withdrawFor(_toaddress);

      return true;
    }

    require(emergencyClose, 'Poll [withdrawFor]: cannot withdraw from Poll of Burn type.');
    _withdrawFor(_toaddress);

    return true;
  }

  function unsafeLoopWithdraw(address[] memory _addressList) external onlyFinished nonReentrant returns (bool) {
    if (burnType == false) {
      for (uint256 i = 0; i < _addressList.length; i++) {
        _withdrawFor(_addressList[i]);
      }

      return true;
    }

    require(emergencyClose, 'Poll [withdrawFor]: cannot withdraw from Poll of Burn type.');
    for (uint256 i = 0; i < _addressList.length; i++) {
      _withdrawFor(_addressList[i]);
    }

    return true;
  }

  function vote(uint256 _proposal, uint256 _amount) external onlyVoteTime nonReentrant returns (bool) {
    require(_proposal != 0 && _proposal < proposals.length, 'Poll [vote]: incorrect proposal to vote');

    // check voter
    if (multiType) {
      require(lockAmountOf[msg.sender] + _amount <= maximumToken, 'Poll [vote]: can not vote more then max limit.');
    } else {
      require(lockAmountOf[msg.sender] == 0, 'Poll [vote]: already voted.');
    }

    require(voteToken.balanceOf(msg.sender) >= _amount, 'Poll [vote]: require balanceOf token to vote');

    require(_amount >= minimumToken && _amount <= maximumToken, 'Poll [vote]: amount not in require range.');
    _vote(msg.sender, _proposal, _amount);

    return true;
  }

  function _addProposals(string[] memory _proposalNames) private {
    for (uint256 i = 0; i < _proposalNames.length; i++) {
      proposals.push(Proposal({desc: _proposalNames[i], voteAmount: 0, valid: true}));
    }

    emit Proposals(_proposalNames);
  }

  function _vote(
    address _voter,
    uint256 _proposal,
    uint256 _amount
  ) private {
    assert(voteToken.transferFrom(_voter, address(this), _amount));

    // if frist vote save to count
    if (voterReceive[_voter].length == 0) {
      voterCount++;
    }

    // save vote data
    VoteReceive memory voteReceive = VoteReceive({vote: _proposal, amount: _amount});
    voterReceive[_voter].push(voteReceive);
    lockAmountOf[_voter] += _amount;

    // add vote point
    proposals[_proposal].voteAmount += _amount;

    // check highest
    if (proposals[_proposal].voteAmount > highestVotedAmount) {
      highestVotedAmount = proposals[_proposal].voteAmount;
      highestVotedIndex = _proposal;
    } else if (proposals[_proposal].voteAmount == highestVotedAmount) {
      highestVotedIndex = 0;
    }

    emit Voted(_voter, _amount, _proposal);
  }

  function _withdrawFor(address _toaddress) private {
    uint256 lockAmount = lockAmountOf[_toaddress];

    lockAmountOf[_toaddress] = 0;
    assert(voteToken.transfer(_toaddress, lockAmount));

    // transfer to owner of locked token
    emit Transfer(_toaddress, lockAmount);
  }
}
