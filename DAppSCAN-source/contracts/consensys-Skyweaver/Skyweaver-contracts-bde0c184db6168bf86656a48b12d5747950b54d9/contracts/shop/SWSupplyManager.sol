pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../utils/Ownable.sol";
import "../interfaces/ISkyweaverAssets.sol";
import "../abstract/AbstractERC1155MintBurn.sol";

import "multi-token-standard/contracts/interfaces/IERC1155.sol";
import "multi-token-standard/contracts/tokens/ERC1155/ERC1155Metadata.sol";
import "multi-token-standard/contracts/utils/SafeMath.sol";


/**
 * This is a contract manages the various SW asset factories
 * and ensures that each factory has constraint access in
 * terms of the id space they are allowed to mint.
 * @dev Mint permissions use range because factory contracts
 *      could be minting large numbers of NFTs or be built
 *      with granular, but efficient permission checks.
 */
contract SWSupplyManager is IERC1155, AbstractERC1155MintBurn, ERC1155Metadata, Ownable {
  using SafeMath for uint256;

  /***********************************|
  |             Variables             |
  |__________________________________*/

  // Factory mapping variables
  mapping(address => bool) internal isFactoryActive;          // Whether an address can print tokens or not
  mapping(address => AssetRange[]) internal mintAccessRanges; // Contains the ID ranges factories are allowed to mint
  AssetRange[] internal lockedRanges;                         // Ranges of IDs that can't be granted permission to mint

  // Supply mapping variables
  mapping (uint256 => uint256) internal currentSupply; // Current supply of token for tokens that have max supply ONLY
  mapping (uint256 => uint256) internal maxSupply;     // Max supply for each token ID (0 indicates no predefined max supply)

  // Struct for mint ID ranges permissions
  struct AssetRange {
    uint256 minID;
    uint256 maxID;
  }

  /***********************************|
  |               Events              |
  |__________________________________*/

  event FactoryActivation(address indexed factory);
  event FactoryShutdown(address indexed factory);
  event MaxSuppliesChanged(uint256[] ids, uint256[] newMaxSupplies);
  event MintPermissionAdded(address indexed factory, AssetRange new_range);
  event MintPermissionRemoved(address indexed factory, AssetRange deleted_range);
  event RangeLocked(AssetRange locked_range);

  /***********************************|
  |     Factory Management Methods    |
  |__________________________________*/

  /**
   * @notice Will ALLOW factory to print some assets specified in `canPrint` mapping
   * @param _factory Address of the factory to activate
   */
  function activateFactory(address _factory) external onlyOwner() {
    isFactoryActive[_factory] = true;
    emit FactoryActivation(_factory);
  }

  /**
   * @notice Will DISALLOW factory to print any asset
   * @param _factory Address of the factory to shutdown
   */
  function shutdownFactory(address _factory) external onlyOwner() {
    isFactoryActive[_factory] = false;
    emit FactoryShutdown(_factory);
  }

  /**
   * @notice Will allow a factory to mint some token ids
   * @param _factory  Address of the factory to update permission
   * @param _minRange Minimum ID (inclusive) in id range that factory will be able to mint
   * @param _maxRange Maximum ID (inclusive) in id range that factory will be able to mint
   */
  function addMintPermission(address _factory, uint256 _minRange, uint256 _maxRange) external onlyOwner() {
    require(_maxRange > 0, "SWSupplyManager#addMintPermission: NULL_RANGE");
    require(_minRange <= _maxRange, "SWSupplyManager#addMintPermission: INVALID_RANGE");

    // Check if new range has an overlap with locked ranges.
    // lockedRanges is expected to be a small array
    for (uint256 i = 0; i < lockedRanges.length; i++) {
      AssetRange memory locked_range = lockedRanges[i];
      require(
        (_maxRange < locked_range.minID) || (locked_range.maxID < _minRange),
        "SWSupplyManager#addMintPermission: OVERLAP_WITH_LOCKED_RANGE"
      );
    }

    // Create and store range struct for _factory
    AssetRange memory range = AssetRange(_minRange, _maxRange);
    mintAccessRanges[_factory].push(range);
    emit MintPermissionAdded(_factory, range);
  }

  /**
   * @notice Will remove the permission a factory has to mint some token ids
   * @param _factory    Address of the factory to update permission
   * @param _rangeIndex Array's index where the range to delete is located for _factory
   */
  function removeMintPermission(address _factory, uint256 _rangeIndex) external onlyOwner() {
    // Will take the last range and put it where the "hole" will be after
    // the AssetRange struct at _rangeIndex is deleted
    uint256 last_index = mintAccessRanges[_factory].length - 1; // won't underflow because of require() statement above
    AssetRange memory range_to_delete = mintAccessRanges[_factory][_rangeIndex]; // Stored for log

    if (_rangeIndex != last_index) {
      AssetRange memory last_range = mintAccessRanges[_factory][last_index]; // Retrieve the range that will be moved
      mintAccessRanges[_factory][_rangeIndex] = last_range;                  // Overwrite the "to-be-deleted" range
    }

    // Delete last element of the array
    mintAccessRanges[_factory].length--; // .pop() for solc >= 0.6.0
    emit MintPermissionRemoved(_factory, range_to_delete);
  }

  /**
   * @notice Will forever prevent new mint permissions for provided ids
   * @dev THIS ACTION IS IRREVERSIBLE, USE WITH CAUTION
   * @dev In order to forever restrict minting of certain ids to a set of factories,
   *      one first needs to call `addMintPermission()` for the corresponding factory
   *      and the corresponding ids, then call this method to prevent further mint
   *      permissions to be granted. One can also remove mint permissions after ids
   *      mint permissions where locked down.
   * @param _range AssetRange struct for range of asset that can't be granted
   *               new mint permission to
   */
  function lockRangeMintPermissions(AssetRange memory _range) public onlyOwner() {
    lockedRanges.push(_range);
    emit RangeLocked(_range);
  }

  /***********************************|
  |    Supplies Management Methods    |
  |__________________________________*/

  /**
   * @notice Set max supply for some token IDs that can't ever be increased
   * @dev Can only decrease the max supply if already set, but can't set it *back* to 0.
   * @param _ids Array of token IDs to set the max supply
   * @param _newMaxSupplies Array of max supplies for each corresponding ID
   */
  function setMaxSupplies(uint256[] calldata _ids, uint256[] calldata _newMaxSupplies) external onlyOwner() {
    require(_ids.length == _newMaxSupplies.length, "SWSupplyManager#setMaxSupply: INVALID_ARRAYS_LENGTH");

    // Can only *decrease* a max supply
    // Can't set max supply back to 0
    for (uint256 i = 0; i < _ids.length; i++ ) {
      if (maxSupply[_ids[i]] > 0) {
        require(
          0 < _newMaxSupplies[i] && _newMaxSupplies[i] < maxSupply[_ids[i]],
          "SWSupplyManager#setMaxSupply: INVALID_NEW_MAX_SUPPLY"
        );
      }
      maxSupply[_ids[i]] = _newMaxSupplies[i];
    }

    emit MaxSuppliesChanged(_ids, _newMaxSupplies);
  }

  /***********************************|
  |      Receiver Method Handler      |
  |__________________________________*/

  /**
   * @notice Prevents receiving Ether or calls to unsuported methods
   */
  function () external {
    revert("UNSUPPORTED_METHOD");
  }

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
  function batchMint(
    address _to,
    uint256[] memory _ids,
    uint256[] memory _amounts,
    bytes memory _data) public
  {
    // Validate assets to be minted
    _validateMints(_ids, _amounts);

    // If hasn't reverted yet, all IDs are allowed for factory
    _batchMint(_to, _ids, _amounts, _data);
  }

  /**
   * @notice Mint _amount of tokens of a given id, if allowed.
   * @param _to      The address to mint tokens to
   * @param _id      Token id to mint
   * @param _amount  The amount to be minted
   * @param _data    Data to pass if receiver is contract
   */
  function mint(address _to, uint256 _id, uint256 _amount, bytes calldata _data) external
  {
    // Put into array for validation
    uint256[] memory ids = new uint256[](1);
    uint256[] memory amounts = new uint256[](1);
    ids[0] = _id;
    amounts[0] = _amount;

    // Validate and mint
    _validateMints(ids, amounts);
    _mint(_to, _id, _amount, _data);
  }

  /**
   * @notice Will validate the ids and amounts to mint
   * @dev This methods assumes ids are sorted by how the ranges are sorted in
   *      the corresponding mintAccessRanges[msg.sender] array. Call will revert
   *      if they are not.
   * @param _ids     Array of ids to mint
   * @param _amounts Array of amount of tokens to mint per id
   */
  function _validateMints(uint256[] memory _ids, uint256[] memory _amounts) internal {
    require(isFactoryActive[msg.sender], "SWSupplyManager#_validateMints: FACTORY_NOT_ACTIVE");

    // Number of mint ranges
    uint256 n_ranges = mintAccessRanges[msg.sender].length;

    // Load factory's default range
    AssetRange memory range = mintAccessRanges[msg.sender][0];
    uint256 range_index = 0;

    // Will make sure that factory is allowed to print all ids
    // and that no max supply is exceeded
    for (uint256 i = 0; i < _ids.length; i++) {
      uint256 id = _ids[i];
      uint256 amount = _amounts[i];
      uint256 max_supply = maxSupply[id];

      // If ID is out of current range, move to next range, else skip.
      // This function only moves forwards in the AssetRange array,
      // hence if _ids are not sorted correctly, the call will fail.
      while (id < range.minID || range.maxID < id) {
        range_index += 1;

        // Load next range. If none left, ID is assumed to be out of all ranges
        require(range_index < n_ranges, "SWSupplyManager#_validateMints: ID_OUT_OF_RANGE");
        range = mintAccessRanges[msg.sender][range_index];
      }

      // If max supply is specified for id
      if (max_supply > 0) {
        uint256 new_supply = currentSupply[id].add(amount);
        require(new_supply <= max_supply, "SWSupplyManager#_validateMints: MAX_SUPPLY_EXCEEDED");
        currentSupply[id] = new_supply;
      }
    }
  }

  /***********************************|
  |         Getter Functions          |
  |__________________________________*/

  /**
   * @notice Get the max supply of multiple asset ID
   * @param _ids Array containing the assets IDs
   * @return The current max supply of each asset ID in _ids
   */
  function getMaxSupplies(uint256[] calldata _ids) external view returns (uint256[] memory) {
    uint256 nIds = _ids.length;
    uint256[] memory maxSupplies = new uint256[](nIds);

    // Iterate over each owner and token ID
    for (uint256 i = 0; i < nIds; i++) {
      maxSupplies[i] = maxSupply[_ids[i]];
    }

    return maxSupplies;
  }

  /**
   * @notice Get the current supply of multiple asset ID
   * @param _ids Array containing the assets IDs
   * @return The current supply of each asset ID in _ids
   */
  function getCurrentSupplies(uint256[] calldata _ids) external view returns (uint256[] memory) {
    uint256 nIds = _ids.length;
    uint256[] memory currentSupplies = new uint256[](nIds);

    // Iterate over each owner and token ID
    for (uint256 i = 0; i < nIds; i++) {
      currentSupplies[i] = currentSupply[_ids[i]];
    }

    return currentSupplies;
  }

  /**
   * @return Returns whether a factory is active or not
   */
  function getFactoryStatus(address _factory) external view returns (bool) {
    return isFactoryActive[_factory];
  }

  /**
   * @return Returns whether the sale has ended or not
   */
  function getFactoryAccessRanges(address _factory) external view returns (AssetRange[] memory) {
    return mintAccessRanges[_factory];
  }

  /**
   * @return Returns all the ranges that are locked
   */
  function getLockedRanges() external view returns (AssetRange[] memory) {
    return lockedRanges;
  }

  /***********************************|
  |          Burning Functions        |
  |__________________________________*/

  /**
   * @notice Burn _amount of tokens of a given id from msg.sender
   * @dev This will not change the current supply tracked in _supplyManagerAddr.
   * @param _id     Asset id to burn
   * @param _amount The amount to be burn
   */
  function burn(
    uint256 _id,
    uint256 _amount)
    external
  {
    _burn(msg.sender, _id, _amount);
  }

  /**
   * @notice Burn _amounts of tokens of given ids from msg.sender
   * @dev This will not change the current supplies tracked in _supplyManagerAddr.
   * @param _ids     Asset id to burn
   * @param _amounts The amount to be burn
   */
  function batchBurn(
    uint256[] calldata _ids,
    uint256[] calldata _amounts)
    external
  {
    _batchBurn(msg.sender, _ids, _amounts);
  }

  /***********************************|
  |           URI Functions           |
  |__________________________________*/

  /**
   * @dev Will update the base URL of token's URI
   * @param _newBaseMetadataURI New base URL of token's URI
   */
  function setBaseMetadataURI(string calldata _newBaseMetadataURI) external onlyOwner() {
    _setBaseMetadataURI(_newBaseMetadataURI);
  }

  /**
   * @dev Will emit default URI log event for corresponding token _id
   * @param _tokenIDs Array of IDs of tokens to log default URI
   */
  function logURIs(uint256[] calldata _tokenIDs) external onlyOwner() {
    _logURIs(_tokenIDs);
  }
}
