// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';

import './access/Adminnable.sol';
import './EventToken.sol';

contract TokenFactory is Adminnable, Ownable {
  uint256 public tokenCount;
  TokenInfo[] public tokenList;
  mapping(address => TokenInfo) public mapEventToken;

  struct TokenInfo {
    uint256 index;
    address addr;
    uint256 timestamp;
    string desc;
  }

  event TokenCreated(address _eventToken, address _creater);

  constructor(IAdminManage _adminManage, address _bigOwner) Adminnable(_adminManage) {
    transferOwnership(_bigOwner);
  }

  function getToken(address _address)
    external
    view
    returns (
      uint256 index,
      address addr,
      uint256 timestamp,
      string memory desc
    )
  {
    require(mapEventToken[_address].addr != address(0), 'TokenFactory [getToken]: Not found Token.');

    TokenInfo memory tokenInfo = mapEventToken[_address];

    return (tokenInfo.index, tokenInfo.addr, tokenInfo.timestamp, tokenInfo.desc);
  }

  function createToken(
    string memory _name,
    string memory _symbol,
    uint256 _initalToken,
    string memory _desc,
    address _mintTo
  ) external onlyAdmin returns (address addr) {
    bytes memory bytecode = _getContractBytecode(_name, _symbol, _initalToken, _mintTo);

    bytes32 salt = keccak256(abi.encodePacked(block.timestamp, msg.sender));
    assembly {
      addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
      if iszero(extcodesize(addr)) {
        revert(0, 0)
      }
    }

    TokenInfo memory tokenInfo = TokenInfo(tokenCount, addr, block.timestamp, _desc);

    tokenList.push(tokenInfo);
    assert(tokenCount + 1 > tokenCount);
    tokenCount++;

    mapEventToken[addr] = tokenInfo;

    emit TokenCreated(address(addr), msg.sender);
  }

  function _getContractBytecode(
    string memory _name,
    string memory _symbol,
    uint256 _initalToken,
    address _mintTo
  ) private view returns (bytes memory) {
    bytes memory bytecode = type(EventToken).creationCode;

    return abi.encodePacked(bytecode, abi.encode(_name, _symbol, _initalToken, adminManage, _mintTo, owner()));
  }
}
