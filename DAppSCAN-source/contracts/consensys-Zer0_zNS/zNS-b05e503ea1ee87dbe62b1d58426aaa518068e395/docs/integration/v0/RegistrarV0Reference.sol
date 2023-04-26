// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

/// @title ERC-721 Non-Fungible Token Standard
/// @dev See https://eips.ethereum.org/EIPS/eip-721
///  Note: the ERC-165 identifier for this interface is 0x80ac58cd.
/* is ERC165 */
interface IERC721 {
  /// @dev This emits when ownership of any NFT changes by any mechanism.
  ///  This event emits when NFTs are created (`from` == 0) and destroyed
  ///  (`to` == 0). Exception: during contract creation, any number of NFTs
  ///  may be created and assigned without emitting Transfer. At the time of
  ///  any transfer, the approved address for that NFT (if any) is reset to none.
  event Transfer(
    address indexed _from,
    address indexed _to,
    uint256 indexed _tokenId
  );

  /// @dev This emits when the approved address for an NFT is changed or
  ///  reaffirmed. The zero address indicates there is no approved address.
  ///  When a Transfer event emits, this also indicates that the approved
  ///  address for that NFT (if any) is reset to none.
  event Approval(
    address indexed _owner,
    address indexed _approved,
    uint256 indexed _tokenId
  );

  /// @dev This emits when an operator is enabled or disabled for an owner.
  ///  The operator can manage all NFTs of the owner.
  event ApprovalForAll(
    address indexed _owner,
    address indexed _operator,
    bool _approved
  );

  /// @notice Count all NFTs assigned to an owner
  /// @dev NFTs assigned to the zero address are considered invalid, and this
  ///  function throws for queries about the zero address.
  /// @param _owner An address for whom to query the balance
  /// @return The number of NFTs owned by `_owner`, possibly zero
  function balanceOf(address _owner) external view returns (uint256);

  /// @notice Find the owner of an NFT
  /// @dev NFTs assigned to zero address are considered invalid, and queries
  ///  about them do throw.
  /// @param _tokenId The identifier for an NFT
  /// @return The address of the owner of the NFT
  function ownerOf(uint256 _tokenId) external view returns (address);

  /// @notice Transfers the ownership of an NFT from one address to another address
  /// @dev Throws unless `msg.sender` is the current owner, an authorized
  ///  operator, or the approved address for this NFT. Throws if `_from` is
  ///  not the current owner. Throws if `_to` is the zero address. Throws if
  ///  `_tokenId` is not a valid NFT. When transfer is complete, this function
  ///  checks if `_to` is a smart contract (code size > 0). If so, it calls
  ///  `onERC721Received` on `_to` and throws if the return value is not
  ///  `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`.
  /// @param _from The current owner of the NFT
  /// @param _to The new owner
  /// @param _tokenId The NFT to transfer
  /// @param data Additional data with no specified format, sent in call to `_to`
  function safeTransferFrom(
    address _from,
    address _to,
    uint256 _tokenId,
    bytes memory data
  ) external payable;

  /// @notice Transfers the ownership of an NFT from one address to another address
  /// @dev This works identically to the other function with an extra data parameter,
  ///  except this function just sets data to "".
  /// @param _from The current owner of the NFT
  /// @param _to The new owner
  /// @param _tokenId The NFT to transfer
  function safeTransferFrom(
    address _from,
    address _to,
    uint256 _tokenId
  ) external payable;

  /// @notice Transfer ownership of an NFT -- THE CALLER IS RESPONSIBLE
  ///  TO CONFIRM THAT `_to` IS CAPABLE OF RECEIVING NFTS OR ELSE
  ///  THEY MAY BE PERMANENTLY LOST
  /// @dev Throws unless `msg.sender` is the current owner, an authorized
  ///  operator, or the approved address for this NFT. Throws if `_from` is
  ///  not the current owner. Throws if `_to` is the zero address. Throws if
  ///  `_tokenId` is not a valid NFT.
  /// @param _from The current owner of the NFT
  /// @param _to The new owner
  /// @param _tokenId The NFT to transfer
  function transferFrom(
    address _from,
    address _to,
    uint256 _tokenId
  ) external payable;

  /// @notice Change or reaffirm the approved address for an NFT
  /// @dev The zero address indicates there is no approved address.
  ///  Throws unless `msg.sender` is the current NFT owner, or an authorized
  ///  operator of the current owner.
  /// @param _approved The new approved NFT controller
  /// @param _tokenId The NFT to approve
  function approve(address _approved, uint256 _tokenId) external payable;

  /// @notice Enable or disable approval for a third party ("operator") to manage
  ///  all of `msg.sender`'s assets
  /// @dev Emits the ApprovalForAll event. The contract MUST allow
  ///  multiple operators per owner.
  /// @param _operator Address to add to the set of authorized operators
  /// @param _approved True if the operator is approved, false to revoke approval
  function setApprovalForAll(address _operator, bool _approved) external;

  /// @notice Get the approved address for a single NFT
  /// @dev Throws if `_tokenId` is not a valid NFT.
  /// @param _tokenId The NFT to find the approved address for
  /// @return The approved address for this NFT, or the zero address if there is none
  function getApproved(uint256 _tokenId) external view returns (address);

  /// @notice Query if an address is an authorized operator for another address
  /// @param _owner The address that owns the NFTs
  /// @param _operator The address that acts on behalf of the owner
  /// @return True if `_operator` is an approved operator for `_owner`, false otherwise
  function isApprovedForAll(address _owner, address _operator)
    external
    view
    returns (bool);
}

interface IERC721Metadata is IERC721 {
  /**
   * @dev Returns the token collection name.
   */
  function name() external view returns (string memory);

  /**
   * @dev Returns the token collection symbol.
   */
  function symbol() external view returns (string memory);

  /**
   * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
   */
  function tokenURI(uint256 tokenId) external view returns (string memory);
}

interface IERC721Enumerable is IERC721 {
  /**
   * @dev Returns the total amount of tokens stored by the contract.
   */
  function totalSupply() external view returns (uint256);

  /**
   * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
   * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
   */
  function tokenOfOwnerByIndex(address owner, uint256 index)
    external
    view
    returns (uint256 tokenId);

  /**
   * @dev Returns a token ID at a given `index` of all the tokens stored by the contract.
   * Use along with {totalSupply} to enumerate all tokens.
   */
  function tokenByIndex(uint256 index) external view returns (uint256);
}

interface RegistrarV0Reference is IERC721Metadata, IERC721Enumerable {
  // Emitted when a controller is removed
  event ControllerAdded(address indexed controller);

  // Emitted whenever a controller is removed
  event ControllerRemoved(address indexed controller);

  // Emitted whenever a new domain is created
  event DomainCreated(
    uint256 indexed id, // nft-id
    string name, // human-readable name (dorg, remscar)  dorg.remscar -> remscar
    uint256 indexed nameHash, // remscar -> hash(remscar)
    uint256 indexed parent // id of parent hash(dorg)
  );

  function domainExists(uint256 id) external view returns (bool);

  // Authorises a controller, who can register domains.
  function addController(address controller) external;

  // Revoke controller permission for an address.
  function removeController(address controller) external;

  // Whether or not a domain specific by an id is available.
  function available(uint256 id) external view returns (bool);

  // Returns the original creator of  domain
  function creatorOf(uint256 id) external view returns (address);

  // Lock a domains metadata from being modified, can only be called by domain owner and if the metadata is unlocked
  function lockDomainMetadata(uint256 id) external;

  // Unlocks a domains metadata, can only be called by the address that locked the metadata
  function unlockDomainMetadata(uint256 id) external;

  // Checks if a domains metadata is locked
  function domainMetadataLocked(uint256 id) external view returns (bool);

  // Returns the address which locked the domain metadata
  function domainMetadataLockedBy(uint256 id) external view returns (address);

  // Function used by controllers to register a new domain
  function registerDomain(
    uint256 parent,
    string memory name,
    address domainOwner
  ) external;
}
