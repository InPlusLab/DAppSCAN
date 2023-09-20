// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721PausableUpgradeable.sol";
import "./interfaces/IRegistrar.sol";

// SWC-135-Code With No Effects: L8-11
contract Registrar is
  IRegistrar,
  OwnableUpgradeable,
  ERC721PausableUpgradeable
{
  // Data recorded for each domain
  struct DomainRecord {
    address minter;
    bool metadataLocked;
    address metadataLockedBy;
    address controller;
    uint256 royaltyAmount;
  }

  // A map of addresses that are authorised to register domains.
  mapping(address => bool) public controllers;

  // A mapping of domain id's to domain data
  // This essentially expands the internal ERC721's token storage to additional fields
  mapping(uint256 => DomainRecord) public records;

  modifier onlyController() {
    require(controllers[msg.sender], "Zer0 Registrar: Not controller");
    _;
  }

  modifier onlyOwnerOf(uint256 id) {
    require(ownerOf(id) == msg.sender, "Zer0 Registrar: Not owner");
    _;
  }

  function initialize() public initializer {
    __Ownable_init();
    __ERC721_init("Zer0 Name Service", "ZNS");

    // create the root domain
    _createDomain(0, msg.sender, msg.sender, address(0));
  }

  /*
    External Methods
  */
  // SWC-135-Code With No Effects: L51-67
  /**
    @notice Authorizes a controller to control the registrar
    @param controller The address of the controller
   */
  function addController(address controller) external override onlyOwner {
    controllers[controller] = true;
    emit ControllerAdded(controller);
  }

  /**
    @notice Unauthorizes a controller to control the registrar
    @param controller The address of the controller
   */
  function removeController(address controller) external override onlyOwner {
    controllers[controller] = false;
    emit ControllerRemoved(controller);
  }

  /**
    @notice Registers a new (sub) domain
    @param parentId The parent domain
    @param name The name of the domain
    @param domainOwner the owner of the new domain
    @param minter the minter of the new domain
   */
  function registerDomain(
    uint256 parentId,
    string memory name,
    address domainOwner,
    address minter
  ) external override onlyController returns (uint256) {
    // Create the child domain under the parent domain
    uint256 labelHash = uint256(keccak256(bytes(name)));
    address controller = msg.sender;

    // Domain parents must exist
    require(_exists(parentId), "Zer0 Registrar: No parent");

    // Calculate the new domain's id and create it
    uint256 domainId = uint256(
      keccak256(abi.encodePacked(parentId, labelHash))
    );
    _createDomain(domainId, domainOwner, minter, controller);

    emit DomainCreated(domainId, name, labelHash, parentId, minter, controller);

    return domainId;
  }

  /**
    @notice Sets the domain royalty amount
    @param id The domain to set on
    @param amount The royalty amount
   */
  function setDomainRoyaltyAmount(uint256 id, uint256 amount)
    external
    override
    onlyOwnerOf(id)
  {
    require(!isDomainMetadataLocked(id), "Zer0 Registrar: Metadata locked");

    records[id].royaltyAmount = amount;
    emit RoyaltiesAmountChanged(id, amount);
  }

  /**
    @notice Sets the domain metadata uri
    @param id The domain to set on
    @param uri The uri to set
   */
  function setDomainMetadataUri(uint256 id, string memory uri)
    external
    override
    onlyOwnerOf(id)
  {
    require(!isDomainMetadataLocked(id), "Zer0 Registrar: Metadata locked");

    _setTokenURI(id, uri);
    emit MetadataChanged(id, uri);
  }

  /**
    @notice Locks a domains metadata uri
    @param id The domain to lock
   */
  function lockDomainMetadata(uint256 id) external override onlyOwnerOf(id) {
    require(!isDomainMetadataLocked(id), "Zer0 Registrar: Metadata locked");

    _lockMetadata(id, msg.sender);
  }

  /**
    @notice Locks a domains metadata uri on behalf the owner
    @param id The domain to lock
   */
  function lockDomainMetadataForOwner(uint256 id)
    external
    override
    onlyController
  {
    require(!isDomainMetadataLocked(id), "Zer0 Registrar: Metadata locked");

    address domainOwner = ownerOf(id);
    _lockMetadata(id, domainOwner);
  }

  /**
    @notice Unlocks a domains metadata uri
    @param id The domain to unlock
   */
  function unlockDomainMetadata(uint256 id) external override {
    require(isDomainMetadataLocked(id), "Zer0 Registrar: Not locked");
    require(
      domainMetadataLockedBy(id) == msg.sender,
      "Zer0 Registrar: Not locker"
    );

    _unlockMetadata(id);
  }

  /*
    Public View
  */

  /**
    @notice Returns whether or not a domain is available to be created
    @param id The domain
   */
  function isAvailable(uint256 id) public view override returns (bool) {
    bool notRegistered = !_exists(id);
    return notRegistered;
  }

  /**
    @notice Returns whether or not a domain is exists
    @param id The domain
   */
  function domainExists(uint256 id) public view override returns (bool) {
    bool domainNftExists = _exists(id);
    return domainNftExists;
  }

  /**
    @notice Returns the original minter of a domain
    @param id The domain
   */
  function minterOf(uint256 id) public view override returns (address) {
    address minter = records[id].minter;
    return minter;
  }

  /**
    @notice Returns whether or not a domain's metadata is locked
    @param id The domain
   */
  function isDomainMetadataLocked(uint256 id)
    public
    view
    override
    returns (bool)
  {
    bool isLocked = records[id].metadataLocked;
    return isLocked;
  }

  /**
    @notice Returns who locked a domain's metadata
    @param id The domain
   */
  function domainMetadataLockedBy(uint256 id)
    public
    view
    override
    returns (address)
  {
    address lockedBy = records[id].metadataLockedBy;
    return lockedBy;
  }

  /**
    @notice Returns the controller which created the domain on behalf of a user
    @param id The domain
   */
  function domainController(uint256 id) public view override returns (address) {
    address controller = records[id].controller;
    return controller;
  }

  /**
    @notice Returns the current royalty amount for a domain
    @param id The domain
   */
  function domainRoyaltyAmount(uint256 id)
    public
    view
    override
    returns (uint256)
  {
    uint256 amount = records[id].royaltyAmount;
    return amount;
  }

  /*
    Internal Methods
  */

  // internal - creates a domain
  function _createDomain(
    uint256 domainId,
    address domainOwner,
    address minter,
    address controller
  ) internal {
    // Create the NFT and register the domain data
    _safeMint(domainOwner, domainId);
    records[domainId] = DomainRecord({
      minter: minter,
      metadataLocked: false,
      metadataLockedBy: address(0),
      controller: controller,
      royaltyAmount: 0
    });
  }

  // internal - locks a domains metadata
  function _lockMetadata(uint256 id, address locker) internal {
    records[id].metadataLocked = true;
    records[id].metadataLockedBy = locker;

    emit MetadataLocked(id, locker);
  }

  // internal - unlocks a domains metadata
  function _unlockMetadata(uint256 id) internal {
    records[id].metadataLocked = false;
    records[id].metadataLockedBy = address(0);

    emit MetadataUnlocked(id);
  }
}
