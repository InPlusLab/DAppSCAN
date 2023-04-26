// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721HolderUpgradeable.sol";

import "./interfaces/IBasicController.sol";
import "./interfaces/IRegistrar.sol";

contract BasicController is
  IBasicController,
  ContextUpgradeable,
  ERC165Upgradeable,
  ERC721HolderUpgradeable
{
  IRegistrar private registrar;
  uint256 private rootDomain;

  modifier authorized(uint256 domain) {
    require(registrar.domainExists(domain), "Zer0 Controller: Invalid Domain");
    require(
      registrar.ownerOf(domain) == _msgSender(),
      "Zer0 Controller: Not Authorized"
    );
    _;
  }

  function initialize(IRegistrar _registrar) public initializer {
    __ERC165_init();
    __Context_init();

    registrar = _registrar;
    rootDomain = 0x0;
  }

  function registerDomain(string memory domain, address owner)
    public
    override
    authorized(rootDomain)
  {
    registerSubdomain(rootDomain, domain, owner);
  }

  function registerSubdomain(
    uint256 parentId,
    string memory label,
    address owner
  ) public override authorized(parentId) {
    address minter = _msgSender();
    uint256 id = registrar.registerDomain(parentId, label, owner, minter);

    emit RegisteredDomain(label, id, parentId, owner, minter);
  }

  function registerSubdomainExtended(
    uint256 parentId,
    string memory label,
    address owner,
    string memory metadata,
    uint256 royaltyAmount,
    bool lockOnCreation
  ) external authorized(parentId) {
    address minter = _msgSender();
    address controller = address(this);

    uint256 id = registrar.registerDomain(parentId, label, controller, minter);
    registrar.setDomainMetadataUri(id, metadata);
    registrar.setDomainRoyaltyAmount(id, royaltyAmount);
    registrar.transferFrom(controller, owner, id);

    if (lockOnCreation) {
      registrar.lockDomainMetadataForOwner(id);
    }

    emit RegisteredDomain(label, id, parentId, owner, minter);
  }
}
