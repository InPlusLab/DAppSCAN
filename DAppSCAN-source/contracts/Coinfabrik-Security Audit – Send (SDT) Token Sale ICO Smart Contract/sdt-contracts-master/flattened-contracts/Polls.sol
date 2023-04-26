pragma solidity ^0.4.18;

// File: contracts/ISnapshotToken.sol

/**
 * @title Snapshot Token
 *
 * @dev Snapshot Token interface
 * @dev https://send.sd/token
 */
interface ISnapshotToken {
  function requestSnapshots(uint256 _blockNumber) public;
  function takeSnapshot(address _owner) public returns(uint256);
}

// File: zeppelin-solidity/contracts/ownership/Ownable.sol

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
  address public owner;


  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);


  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  function Ownable() public {
    owner = msg.sender;
  }


  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }


  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) public onlyOwner {
    require(newOwner != address(0));
    OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }

}

// File: contracts/Polls.sol

/**
 * @title Send token
 *
 * @dev Implementation of Send Consensus network Standard
 * @dev https://send.sd/token
 */
contract Polls is Ownable {
  Poll public poll;
  ISnapshotToken public token;

  // uint256 blockNumber => address voter => bool voted
  mapping (uint256 => mapping(address => bool)) internal voted;
  // uint256 blockNumber => uint256 option => uint256 result
  mapping (uint256 => mapping(uint256 => uint256)) internal results;

  struct Poll {
    uint256 block;
    uint256 minimumTokens;
    uint256 endTime;
  }

  event PollCreated(
      uint256 block,
      bytes32 question,
      bytes32[] options,
      uint256 minimumTokens,
      uint256 endTime
  );

  event ResultRevealed(
      uint256 pollIDM,
      uint256 pollOption,
      uint256 pollResult
  );

  function Polls(address _token) public {
    require(_token != 0x0);
    token = ISnapshotToken(_token);
  }

  /**
   * @dev Create a poll
   * @dev _question and _options parameters are only for logging
   * @notice Only verified addresses
   * @param _question An string to be logged on poll creation
   * @param _options An array of strings to be logged on poll creation
   * @param _minimumTokens Minimum number of tokens to vote
   * @param _endTime Poll end time
   */
  function createPoll(
      bytes32 _question,
      bytes32[] _options,
      uint256 _minimumTokens,
      uint256 _endTime
  ) public onlyOwner {
    poll.block = block.number;
    poll.minimumTokens = _minimumTokens;
    poll.endTime = _endTime;

    token.requestSnapshots(block.number);

    PollCreated(
      block.number,
      _question,
      _options,
      _minimumTokens,
      _endTime
    );
  }

  /**
   * @dev vote
   * @dev will fail if doesnt meet minimumTokens requirement on poll dates
   * @notice Only once per address per poll
   * @param _option Index of option to vote (first option is 0)
   */
  function vote(uint256 _option) public {
    require(poll.endTime >= block.timestamp);
    require(!voted[poll.block][msg.sender]);
    require(token.takeSnapshot(msg.sender) >= poll.minimumTokens);

    voted[poll.block][msg.sender] = true;
    results[poll.block][_option] = results[poll.block][_option] + 1;
  }

  /**
   * @dev get results for option
   * @param _option Index of option to check (first option is 0)
   */
  function showResults(uint256 _option) public view returns (uint256) {
    require(poll.endTime <= block.timestamp);

    return results[poll.block][_option];
  }

  /**
   * @dev issue an event with result for option
   * @param _option Index of option to check (first option is 0)
   */
  function logResults(uint256 _option) public onlyOwner {
    ResultRevealed(poll.block, _option, showResults(_option));
  }
}
