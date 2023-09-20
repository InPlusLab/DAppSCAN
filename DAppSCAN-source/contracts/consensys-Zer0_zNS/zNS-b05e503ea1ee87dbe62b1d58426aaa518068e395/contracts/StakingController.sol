// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import "@openzeppelin/contracts-upgradeable/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721HolderUpgradeable.sol";

import "./interfaces/IRegistrar.sol";

contract StakingController is
  Initializable,
  ContextUpgradeable,
  ERC165Upgradeable,
  ERC721HolderUpgradeable
{
  using ECDSAUpgradeable for bytes32;
  using SafeERC20Upgradeable for IERC20Upgradeable;

  IERC20Upgradeable private infinity;
  IRegistrar private registrar;
  address private controller;

  mapping(bytes32 => bool) private approvedBids;

  event DomainBidPlaced(
    bytes32 indexed unsignedRequestHash,
    string indexed bidIPFSHash,
    bytes indexed signature
  );

  event DomainBidApproved(string indexed bidIdentifier);

  event DomainBidFulfilled(
    string indexed bidIdentifier,
    string name,
    address recoveredbidder,
    uint256 indexed id,
    uint256 indexed parentID
  );

  modifier authorizedOwner(uint256 domain) {
    require(registrar.domainExists(domain), "ZNS: Invalid Domain");
    require(
      registrar.ownerOf(domain) == _msgSender(),
      "ZNS: Not Authorized Owner"
    );
    _;
  }

  function initialize(IRegistrar _registrar, IERC20Upgradeable _infinity)
    public
    initializer
  {
    __ERC165_init();
    __Context_init();

    infinity = _infinity;
    registrar = _registrar;
    controller = address(this);
  }

  /**
      @notice placeDomainBid allows a user to send a request for a new sub domain to a domains owner
      @param parentId is the id number of the parent domain to the sub domain being requested
      @param unsignedRequestHash is the un-signed hashed data for a domain bid request
      @param signature is the signature used to sign the request hash
      @param bidIPFSHash is the IPFS hash containing the bids params(ex: name being requested, amount, stc)
      @dev the IPFS hash must be emitted as a string here for the front end to be able to recover the bid info
      @dev signature is emitted here so that the domain owner approving the bid can use the recover function to check that
            the bid information in the IPFS hash matches the bid information used to create the signed message
    **/
  function placeDomainBid(
    uint256 parentId,
    bytes32 unsignedRequestHash,
    bytes memory signature,
    string memory bidIPFSHash
  ) external {
    require(registrar.domainExists(parentId), "ZNS: Invalid Domain");
    emit DomainBidPlaced(unsignedRequestHash, bidIPFSHash, signature);
  }

  /**
      @notice approveDomainBid approves a domain bid, allowing the domain to be created.
      @param parentId is the id number of the parent domain to the sub domain being requested
      @param bidIPFSHash is the IPFS hash of the bids information
      @param signature is the signed hashed data for a domain bid request
    **/
  // SWC-105-Unprotected Ether Withdrawal: L92-101
  function approveDomainBid(
    uint256 parentId,
    string memory bidIPFSHash,
    bytes memory signature
  ) external authorizedOwner(parentId) {
    bytes32 hashOfSig = keccak256(abi.encode(signature));
    approvedBids[hashOfSig] = true;
    emit DomainBidApproved(bidIPFSHash);
  }

  /**
      @notice Fulfills a domain bid, creating the domain.
        Transfers tokens from bidders wallet into controller.
      @param parentId is the id number of the parent domain to the sub domain being requested
      @param bidAmount is the uint value of the amount of infinity bid
      @param royaltyAmount is the royalty amount the creator sets for resales on zAuction
      @param metadata is the IPFS hash of the new domains information
      @dev this is the same IPFS hash that contains the bids information as this is just stored on its own feild in the metadata
      @param name is the name of the new domain being created
      @param bidIPFSHash is the IPFS hash containing the bids params(ex: name being requested, amount, stc)
      @param signature is the signature of the bidder
      @param lockOnCreation is a bool representing whether or not the metadata for this domain is locked
      @param recipient is the address receiving the new domain
    **/
  // SWC-122-Lack of Proper Signature Verification: L121-153
  function fulfillDomainBid(
    uint256 parentId,
    uint256 bidAmount,
    uint256 royaltyAmount,
    string memory bidIPFSHash,
    string memory name,
    string memory metadata,
    bytes memory signature,
    bool lockOnCreation,
    address recipient
  ) external {
    bytes32 recoveredBidHash = createBid(
      parentId,
      bidAmount,
      bidIPFSHash,
      name
    );
    // SWC-117-Signature Malleability: L135
    address recoveredBidder = recover(recoveredBidHash, signature);
    require(recipient == recoveredBidder, "ZNS: bid info doesnt match/exist");
    bytes32 hashOfSig = keccak256(abi.encode(signature));
    require(approvedBids[hashOfSig] == true, "ZNS: has been fullfilled");
    infinity.safeTransferFrom(recoveredBidder, controller, bidAmount);
    uint256 id = registrar.registerDomain(
      parentId,
      name,
      controller,
      recoveredBidder
    );
    registrar.setDomainMetadataUri(id, metadata);
    registrar.setDomainRoyaltyAmount(id, royaltyAmount);
    registrar.transferFrom(controller, recoveredBidder, id);
    if (lockOnCreation) {
      registrar.lockDomainMetadataForOwner(id);
    }
    approvedBids[hashOfSig] = false;
    emit DomainBidFulfilled(metadata, name, recoveredBidder, id, parentId);
  }

  /**
      @notice recover allows the un-signed hashed data of a domain request to be recovered
      @notice unsignedRequestHash is the un-signed hash of the request being recovered
      @notice signature is the signature the hash was signed with
    **/
  function recover(bytes32 unsignedRequestHash, bytes memory signature)
    public
    pure
    returns (address)
  {
    return unsignedRequestHash.toEthSignedMessageHash().recover(signature);
  }

  /**
      @notice createBid is a pure function  that creates a bid hash for the end user
      @param parentId is the ID of the domain where the sub domain is being requested
      @param bidAmount is the amount being bid for the domain
      @param bidIPFSHash is the IPFS hash that contains the bids information
      @param name is the name of the sub domain being requested
      **/
  function createBid(
    uint256 parentId,
    uint256 bidAmount,
    string memory bidIPFSHash,
    string memory name
  ) public pure returns (bytes32) {
    return keccak256(abi.encode(parentId, bidAmount, bidIPFSHash, name));
  }
}
