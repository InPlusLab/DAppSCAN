// SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165Upgradeable {
  /**
   * @dev Returns true if this contract implements the interface defined by
   * `interfaceId`. See the corresponding
   * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
   * to learn more about how these ids are created.
   *
   * This function call must use less than 30 000 gas.
   */
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IBasicController is IERC165Upgradeable {
  event RegisteredDomain(
    string name,
    uint256 indexed id,
    address indexed owner,
    address indexed creator
  );

  event RegisteredSubdomain(
    string name,
    uint256 indexed id,
    uint256 indexed parent,
    address indexed owner,
    address creator
  );

  /**
    @notice Registers a new top level domain
    @param domain The name of the domain
    @param owner Who the owner of the domain should be
   */
  function registerDomain(string memory domain, address owner) external;

  /**
    @notice Registers a new sub domain
    @param parentId The id of the parent domain
    @param label The name of the sub domain
    @param owner The owner of the new sub domain 
 */
  function registerSubdomain(
    uint256 parentId,
    string memory label,
    address owner
  ) external;
}
