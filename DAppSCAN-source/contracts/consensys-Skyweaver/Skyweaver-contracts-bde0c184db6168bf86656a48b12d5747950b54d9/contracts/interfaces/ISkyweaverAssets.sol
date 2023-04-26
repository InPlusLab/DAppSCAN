pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./ISWSupplyManager.sol";


contract ISkyweaverAssets is ISWSupplyManager {
  // Supply Management
  function mint(address _to, uint256 _id, uint256 _amount, bytes calldata _data) external;
  function batchMint(address _to, uint256[] calldata _ids, uint256[] calldata _amounts, bytes calldata _data) external;
  function burn(uint256 _id, uint256 _amount) external;
  function batchBurn(uint256[] calldata _ids, uint256[] calldata _amounts) external;

  // URI
  function uri(uint256 _id) external view returns (string memory);
  function setBaseMetadataURI(string calldata _newBaseMetadataURI) external;
  function logURIs(uint256[] calldata _tokenIDs) external;

  // ERC-1155
  function safeBatchTransferFrom(address _from, address _to, uint256[] calldata _ids, uint256[] calldata _amounts, bytes calldata _data) external;
  function safeTransferFrom(address _from, address _to, uint256 _id, uint256 _amount, bytes calldata _data) external;
}