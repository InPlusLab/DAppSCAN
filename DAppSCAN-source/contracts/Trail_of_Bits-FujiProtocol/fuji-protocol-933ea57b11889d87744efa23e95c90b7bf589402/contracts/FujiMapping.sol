// SPDX-License-Identifier: MIT
//FujiMapping for two addresses

pragma solidity ^0.8.0;

import "./abstracts/claimable/Claimable.sol";

contract FujiMapping is Claimable {
  // Address 1 =>  Address 2 (e.g. erc20 => cToken, contract a L1 => contract b L2, etc)
  mapping(address => address) public addressMapping;

  // URI for mapping
  string public uri;

  /**
   * @dev Adds a two address Mapping
   * @param _addr1: key address for mapping (erc20, provider)
   * @param _addr2: result address (cToken, erc20)
   */
  function setMapping(address _addr1, address _addr2) public onlyOwner {
    addressMapping[_addr1] = _addr2;
  }

  /**
   * @dev Sets a new URI for all token types, by relying on the token type ID
   */
  function setURI(string memory newUri) public onlyOwner {
    uri = newUri;
  }
}
