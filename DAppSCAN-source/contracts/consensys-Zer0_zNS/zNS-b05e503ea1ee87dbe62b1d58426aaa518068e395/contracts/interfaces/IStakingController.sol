// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import "@openzeppelin/contracts-upgradeable/introspection/IERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";

interface IStakingController is IERC165Upgradeable, IERC721ReceiverUpgradeable {
  event DomainBidPlaced(
    bytes32 indexed signedRequestHash,
    string bidIPFSHash,
    bytes indexed signature
  );

  event DomainBidApproved(string bidIdentifier);

  event DomainBidFulfilled(
    string indexed bidIdentifier,
    string name,
    address recoveredbidder,
    uint256 indexed id,
    uint256 indexed parentID
  );

  /**
    @notice placeDomainBid allows a user to send a request for a new sub domain to a domains owner
    @param signedRequestHash is the hashed data for a domain request
    @param signature is the signature used to sign the request hash
    @param bidIPFSHash is the IPFS hash containing the bids params(ex: name being requested, amount, stc)
    @dev the IPFS hash must be emitted as a string here for the front end to be able to recover the bid info
    @dev signature is emitted here so that the domain owner approving the bid can use the recover function to check that
          the bid information in the IPFS hash matches the bid information used to create the signed message
  **/
  function placeDomainBid(
    bytes32 signedRequestHash,
    bytes memory signature,
    string memory bidIPFSHash
  ) external;

  /**
    @notice approveDomainBid approves a domain bid, allowing the domain to be created.
    @param parentId is the id number of the parent domain to the sub domain being requested
    @param bidIPFSHash is the IPFS hash of the bids information
    @param signedRequestHash is the signed hashed data for a domain bid request
  **/
  function approveDomainBid(
    uint256 parentId,
    string memory bidIPFSHash,
    bytes32 signedRequestHash
  ) external;

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
  ) external;

  /**
    @notice recover allows the un-signed hashed data of a domain request to be recovered
    @notice requestHash is the hash of the request being recovered
    @notice signature is the signature the hash was created with
  **/
  function recover(bytes32 requestHash, bytes memory signature)
    external
    pure
    returns (address);

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
  ) external pure returns (bytes32);
}
