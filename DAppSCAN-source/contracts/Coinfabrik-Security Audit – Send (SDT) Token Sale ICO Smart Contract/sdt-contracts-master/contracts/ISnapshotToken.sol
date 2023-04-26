pragma solidity ^0.4.18;


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
