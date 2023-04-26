// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import './Poll.sol';
import '../access/Adminnable.sol';

contract PollFactory is Adminnable {
  uint256 public pollCount;
  PollInfo[] public polls;
  mapping(address => PollInfo) public addressToPoll;

  struct PollInfo {
    uint256 index;
    address addr;
    uint256 timestamp;
  }

  event PollCreated(address _poll, address indexed _creater, string indexed _name);

  constructor(IAdminManage _admin) Adminnable(_admin) {}

  function createPoll(
    IERC20Burnable _voteToken,
    string memory _question,
    string memory _desc,
    string memory _name,
    uint256 _startBlock,
    uint256 _endBlock,
    uint256 _minimumToken,
    uint256 _maximumToken,
    bool _burnType,
    bool _multiType,
    string[] memory _proposals
  ) external onlyAdmin returns (address addr) {
    bytes memory bytecode = getContractBytecode(getAdminManage(), _voteToken, _question, _desc, _name);

    bytes32 salt = keccak256(abi.encodePacked(block.number, msg.sender));

    assembly {
      addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
      if iszero(extcodesize(addr)) {
        revert(0, 0)
      }
    }

    Poll(addr).initialize(_startBlock, _endBlock, _minimumToken, _maximumToken, _burnType, _multiType, _proposals);

    PollInfo memory pollInfo = PollInfo(pollCount, addr, block.timestamp);

    polls.push(pollInfo);
    assert(pollCount + 1 > pollCount);
    pollCount++;

    addressToPoll[addr] = pollInfo;

    emit PollCreated(addr, msg.sender, _name);
  }

  function getContractBytecode(
    address _admin,
    IERC20Burnable _voteToken,
    string memory _question,
    string memory _desc,
    string memory _name
  ) private pure returns (bytes memory) {
    bytes memory bytecode = type(Poll).creationCode;

    return abi.encodePacked(bytecode, abi.encode(_admin, _voteToken, _question, _desc, _name));
  }
}
