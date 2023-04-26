// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IHarvester {
  struct Transaction {
    address to;
    bytes data;
  }

  function getHarvestTransaction(uint256 _farmProtocolNum, bytes memory _data)
    external
    returns (address claimedToken, Transaction memory transaction);
}
