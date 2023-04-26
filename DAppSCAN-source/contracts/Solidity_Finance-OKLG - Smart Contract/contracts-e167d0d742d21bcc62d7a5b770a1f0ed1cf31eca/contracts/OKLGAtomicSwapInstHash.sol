// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/**
 * @title OKLGAtomicSwapInstHash
 * @dev Hash an address, timestamp, amount like that happens in OKLGAtomicSwapInstance.sol
 */
contract OKLGAtomicSwapInstHash {
  function hash(
    address _addy,
    uint256 _ts,
    uint256 _amount
  ) external pure returns (bytes32) {
    return sha256(abi.encodePacked(_addy, _ts, _amount));
  }
}
