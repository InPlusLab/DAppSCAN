pragma solidity ^0.4.18;

import './ISnapshotToken.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import 'zeppelin-solidity/contracts/token/StandardToken.sol';


/**
 * @title Snapshot Token
 *
 * @dev Snapshot Token implementtion
 * @dev https://send.sd/token
 */
contract SnapshotToken is ISnapshotToken, StandardToken, Ownable {
  uint256 public snapshotBlock;

  mapping (address => Snapshot) internal snapshots;

  struct Snapshot {
    uint256 block;
    uint256 balance;
  }

  address public polls;

  modifier isPolls() {
    require(msg.sender == address(polls));
    _;
  }

  /**
   * @dev Remove Verified status of a given address
   * @notice Only contract owner
   * @param _address Address to unverify
   */
  function setPolls(address _address) public onlyOwner {
    polls = _address;
  }

  /**
   * @dev Extend OpenZeppelin's BasicToken transfer function to store snapshot
   * @param _to The address to transfer to.
   * @param _value The amount to be transferred.
   */
  function transfer(address _to, uint256 _value) public returns (bool) {
    takeSnapshot(msg.sender);
    takeSnapshot(_to);
    return BasicToken.transfer(_to, _value);
  }

  /**
   * @dev Extend OpenZeppelin's StandardToken transferFrom function to store snapshot
   * @param _from address The address which you want to send tokens from
   * @param _to address The address which you want to transfer to
   * @param _value uint256 the amount of tokens to be transferred
   */
  function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
    takeSnapshot(_from);
    takeSnapshot(_to);
    return StandardToken.transferFrom(_from, _to, _value);
  }

  /**
   * @dev Take snapshot
   * @param _owner address The address to take snapshot from
   */
  function takeSnapshot(address _owner) public returns(uint256) {
    if (snapshots[_owner].block < snapshotBlock) {
      snapshots[_owner].block = snapshotBlock;
      snapshots[_owner].balance = balanceOf(_owner);
    }
    return snapshots[_owner].balance;
  }

  /**
   * @dev Set snacpshot block
   * @param _blockNumber uint256 The new blocknumber for snapshots
   */
  function requestSnapshots(uint256 _blockNumber) public isPolls {
    snapshotBlock = _blockNumber;
  }
}
