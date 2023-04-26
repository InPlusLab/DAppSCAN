pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

/**
 * This is a contract manages the various SW asset factories
 * and ensures that each factory has constraint access in
 * terms of the id space they are allowed to mint.
 */
interface ISWSupplyManager {

  /***********************************|
  |               Events              |
  |__________________________________*/

  event FactoryActivation(address indexed factory);
  event FactoryShutdown(address indexed factory);
  event MintPermissionAdded(address indexed factory, AssetRange new_range);
  event MintPermissionRemoved(address indexed factory, AssetRange deleted_range);

  // Struct for mint ID ranges permissions
  struct AssetRange {
    uint256 minID;
    uint256 maxID;
  }

  /***********************************|
  |    Supplies Management Methods    |
  |__________________________________*/

  /**
   * @notice Set max supply for some token IDs that can't ever be increased
   * @dev Can only decrease the max supply if already set, but can't set it *back* to 0.
   * @param _ids Array of token IDs to set the max supply
   * @param _supplies Array of max supplies for each corresponding ID
   */
  function setMaxSupplies(uint256[] calldata _ids, uint256[] calldata _supplies) external;

  /***********************************|
  |     Factory Management Methods    |
  |__________________________________*/

  /**
   * @notice Will allow a factory to mint some token ids
   * @param _factory  Address of the factory to update permission
   * @param _minRange Minimum ID (inclusive) in id range that factory will be able to mint
   * @param _maxRange Maximum ID (inclusive) in id range that factory will be able to mint
   */
  function addMintPermission(address _factory, uint256 _minRange, uint256 _maxRange) external;

  /**
   * @notice Will remove the permission a factory has to mint some token ids
   * @param _factory    Address of the factory to update permission
   * @param _rangeIndex Array's index where the range to delete is located for _factory
   */
  function removeMintPermission(address _factory, uint256 _rangeIndex) external;

  /**
   * @notice Will ALLOW factory to print some assets specified in `canPrint` mapping
   * @param _factory Address of the factory to activate
   */
  function activateFactory(address _factory) external;

  /**
   * @notice Will DISALLOW factory to print any asset
   * @param _factory Address of the factory to shutdown
   */
  function shutdownFactory(address _factory) external;

  /**
   * @notice Will forever prevent new mint permissions for provided ids
   * @param _range AssetRange struct for range of asset that can't be granted
   *               new mint permission to
   */
  function lockRangeMintPermissions(AssetRange calldata _range) external;

  /***********************************|
  |          Minting Function         |
  |__________________________________*/

  /**
   * @notice Mint tokens for each ids in _ids
   * @dev This methods assumes ids are sorted by how the ranges are sorted in
   *      the corresponding mintAccessRanges[msg.sender] array. Call might throw
   *      if they are not.
   * @param _to      The address to mint tokens to.
   * @param _ids     Array of ids to mint
   * @param _amounts Array of amount of tokens to mint per id
   * @param _data    Byte array of data to pass to recipient if it's a contract
   */
  function batchMint(address _to, uint256[] calldata _ids, uint256[] calldata _amounts, bytes calldata _data) external;

  /**
   * @notice Mint _amount of tokens of a given id, if allowed.
   * @param _to      The address to mint tokens to
   * @param _id      Token id to mint
   * @param _amount  The amount to be minted
   * @param _data    Data to pass if receiver is contract
   */
  function mint(address _to, uint256 _id, uint256 _amount, bytes calldata _data) external;

  /***********************************|
  |         Getter Functions          |
  |__________________________________*/

  /**
   * @return Returns whether a factory is active or not
   */
  function getFactoryStatus(address _factory) external view returns (bool);

  /**
   * @return Returns whether the sale has ended or not
   */
  function getFactoryAccessRanges(address _factory) external view returns ( AssetRange[] memory);

  /**
   * @notice Get the max supply of multiple asset ID
   * @param _ids Array containing the assets IDs
   * @return The current max supply of each asset ID in _ids
   */
  function getMaxSupplies(uint256[] calldata _ids) external view returns (uint256[] memory);

  /**
   * @notice Get the current supply of multiple asset ID
   * @param _ids Array containing the assets IDs
   * @return The current supply of each asset ID in _ids
   */
  function getCurrentSupplies(uint256[] calldata _ids) external view returns (uint256[] memory);
}
