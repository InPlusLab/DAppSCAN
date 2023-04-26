// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./external/openzeppelin/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title An ownable ERC721
/// @author Brendan Asselstine
/// @notice The owner may change the base URI
contract ERC721Controlled is ERC721, AccessControl {

  /// @notice Emitted when the token is constructed
  event ERC721ControlledInitialized(
    string name,
    string symbol
  );

  /// @notice Emitted when the base URI is set
  event ERC721ControlledBaseURISet(
    string baseURI
  );

  /// @dev Records the total supply of tokens
  uint256 internal _totalSupply;

  /// @notice Initializes a newly created contract
  /// @param name The token name
  /// @param symbol The token symbol
  /// @param baseURI The base URI to use for the token URI
  /// @param admin The admin of the token
  function initialize (
    string memory name,
    string memory symbol,
    string memory baseURI,
    address admin
  ) public initializer {
    ERC721.initialize(name, symbol);
    __setBaseURI(baseURI);
    _setupRole(DEFAULT_ADMIN_ROLE, admin);

    emit ERC721ControlledInitialized(name, symbol);
  }

  /// @notice Sets the base URI of the token.  Only callable by the admin
  /// @param _baseURI The new base URI to use
  function setBaseURI(string memory _baseURI) external onlyAdmin {
    __setBaseURI(_baseURI);
  }

  /// @notice Mints a new token.  Only callable by the admin.
  /// @param to The owner that the token should be minted to.
  /// @return The new token id
  function mint(address to) external onlyAdmin returns (uint256) {
    _totalSupply = _totalSupply.add(1);
    _mint(to, _totalSupply);
    return _totalSupply;
  }

  /// @notice The total number of tokens that have been minted.
  /// @return The total number of tokens.
  function totalSupply() external view returns (uint256) {
    return _totalSupply;
  }

  /// @dev Sets the base URI without any safety checks
  /// @param _baseURI The new base URI
  function __setBaseURI(string memory _baseURI) internal {
    _setBaseURI(_baseURI);

    emit ERC721ControlledBaseURISet(_baseURI);
  }

  /// @dev Requires the msg.sender to have the DEFAULT_ADMIN_ROLE
  modifier onlyAdmin() {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ERC721Controlled/only-admin");
    _;
  }

}
