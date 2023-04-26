// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

interface ControllerV0Reference {
  // Used by an end user to register a subdomain on a given parent domain
  // The user must be the owner of the parent domain
  function registerSubdomain(
    uint256 parentDomain,
    string memory domainName,
    address domainOwner
  ) external;
}
