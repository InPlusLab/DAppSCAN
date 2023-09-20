// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import './OKLGProduct.sol';

/**
 * @title OKLGPasswordManager
 * @dev Logic for storing and retrieving account information from the blockchain.
 */
contract OKLGPasswordManager is OKLGProduct {
  using SafeMath for uint256;

  struct AccountInfo {
    string id;
    uint256 timestamp;
    string iv;
    string ciphertext;
    bool isDeleted;
  }

  mapping(address => mapping(string => uint256)) public userAccountIdIndexes;

  // the normal mapping of all accounts owned by a user
  mapping(address => AccountInfo[]) public userAccounts;

  constructor(address _tokenAddress, address _spendAddress)
    OKLGProduct(uint8(2), _tokenAddress, _spendAddress)
  {}

  function getAllAccounts(address _userAddy)
    external
    view
    returns (AccountInfo[] memory)
  {
    return userAccounts[_userAddy];
  }

  function getAccountById(string memory _id)
    external
    view
    returns (AccountInfo memory)
  {
    AccountInfo[] memory _userInfo = userAccounts[msg.sender];
    // SWC-128-DoS With Block Gas Limit: L47 - L51
    for (uint256 _i = 0; _i < _userInfo.length; _i++) {
      if (_compareStr(_userInfo[_i].id, _id)) {
        return _userInfo[_i];
      }
    }
    return
      AccountInfo({
        id: '',
        timestamp: 0,
        iv: '',
        ciphertext: '',
        isDeleted: false
      });
  }

  function updateAccountById(
    string memory _id,
    string memory _newIv,
    string memory _newAccountData
  ) external returns (bool) {
    AccountInfo[] memory _userInfo = userAccounts[msg.sender];
    uint256 _idx = userAccountIdIndexes[msg.sender][_id];
    require(
      _compareStr(_id, _userInfo[_idx].id),
      'the ID provided does not match the account stored.'
    );
    userAccounts[msg.sender][_idx].iv = _newIv;
    userAccounts[msg.sender][_idx].timestamp = block.timestamp;
    userAccounts[msg.sender][_idx].ciphertext = _newAccountData;
    return true;
  }

  function addAccount(
    string memory _id,
    string memory _iv,
    string memory _ciphertext
  ) external payable {
    _payForService(0);

    require(
      userAccountIdIndexes[msg.sender][_id] == 0,
      'this ID is already being used, the account should be updated instead'
    );
    userAccountIdIndexes[msg.sender][_id] = userAccounts[msg.sender].length;

    userAccounts[msg.sender].push(
      AccountInfo({
        id: _id,
        timestamp: block.timestamp,
        iv: _iv,
        ciphertext: _ciphertext,
        isDeleted: false
      })
    );
  }

  function bulkAddAccounts(AccountInfo[] memory accounts) external payable {
    require(
      accounts.length >= 5,
      'you need a minimum of 5 accounts to add in bulk at a 50% discount service cost'
    );
    _payForService(0);

    for (uint256 _i = 0; _i < accounts.length; _i++) {
      AccountInfo memory _account = accounts[_i];
      userAccounts[msg.sender].push(
        AccountInfo({
          id: _account.id,
          timestamp: block.timestamp,
          iv: _account.iv,
          ciphertext: _account.ciphertext,
          isDeleted: false
        })
      );
    }
  }

  function deleteAccount(string memory _id) external returns (bool) {
    AccountInfo[] memory _userInfo = userAccounts[msg.sender];
    uint256 _idx = userAccountIdIndexes[msg.sender][_id];
    require(
      _compareStr(_id, _userInfo[_idx].id),
      'the ID provided does not match the account stored.'
    );
    userAccounts[msg.sender][_idx].timestamp = block.timestamp;
    userAccounts[msg.sender][_idx].isDeleted = true;
    return true;
  }

  function _compareStr(string memory a, string memory b)
    private
    pure
    returns (bool)
  {
    return (keccak256(abi.encodePacked((a))) ==
      keccak256(abi.encodePacked((b))));
  }
}
