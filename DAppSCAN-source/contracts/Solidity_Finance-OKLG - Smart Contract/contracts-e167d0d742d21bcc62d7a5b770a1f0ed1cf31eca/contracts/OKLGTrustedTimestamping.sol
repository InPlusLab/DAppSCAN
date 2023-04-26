// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import './OKLGProduct.sol';

/**
 * @title OKLGTrustedTimestamping
 * @dev Stores SHA256 data hashes for trusted timestamping implementations.
 */
contract OKLGTrustedTimestamping is OKLGProduct {
  struct DataHash {
    bytes32 dataHash;
    uint256 time;
    string fileName;
    uint256 fileSizeBytes;
  }

  struct Address {
    address addy;
    uint256 time;
  }

  uint256 public totalNumberHashesStored;
  mapping(address => DataHash[]) public addressHashes;
  mapping(bytes32 => Address[]) public fileHashesToAddress;

  event StoreHash(address from, bytes32 dataHash);

  constructor(address _tokenAddress, address _pendAddress)
    OKLGProduct(uint8(3), _tokenAddress, _pendAddress)
  {}

  /**
   * @dev Process transaction and store hash in blockchain
   */
  function storeHash(
    bytes32 dataHash,
    string memory fileName,
    uint256 fileSizeBytes
  ) external payable {
    _payForService(0);

    uint256 theTimeNow = block.timestamp;
    addressHashes[msg.sender].push(
      DataHash({
        dataHash: dataHash,
        time: theTimeNow,
        fileName: fileName,
        fileSizeBytes: fileSizeBytes
      })
    );
    fileHashesToAddress[dataHash].push(
      Address({ addy: msg.sender, time: theTimeNow })
    );
    totalNumberHashesStored++;
    emit StoreHash(msg.sender, dataHash);
  }

  function getHashesForAddress(address _userAddy)
    external
    view
    returns (DataHash[] memory)
  {
    return addressHashes[_userAddy];
  }

  function getAddressesForHash(bytes32 dataHash)
    external
    view
    returns (Address[] memory)
  {
    return fileHashesToAddress[dataHash];
  }
}
