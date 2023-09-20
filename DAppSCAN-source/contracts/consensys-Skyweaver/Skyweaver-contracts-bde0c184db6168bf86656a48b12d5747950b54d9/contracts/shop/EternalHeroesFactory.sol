pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../utils/Ownable.sol";
import "../interfaces/ISWSupplyManager.sol";
import "multi-token-standard/contracts/interfaces/IERC1155.sol";
import "multi-token-standard/contracts/utils/SafeMath.sol";

/**
 * This is a contract allowing users to mint eternal heroes from HorizonGames.
 * Price starts lower and increases
 */
contract EternalHeroesFactory is Ownable {
  using SafeMath for uint256;

  /**
   * TO DO
   *   - Check for SLOADs for stepsFrequency and stepSize in `_buy`
   *   - Add getter function
   */

  /***********************************|
  |        Variables && Events        |
  |__________________________________*/

  // Constants
  uint256 constant internal decimals = 2; // Number of decimals

  // Initiate Variables
  ISWSupplyManager internal factoryManager;  // SkyWeaver Factory manager contract
  IERC1155 internal arcadeumCoin;            // ERC-1155 Arcadeum Coin contract
  uint256 internal arcadeumCoinID;           // ID of ARC token in respective ERC-1155 contract

  // OnReceive Objects
  struct Order {
    address recipient;             // Who receives the tokens
    uint256[] tokensBoughtIDs;     // Token IDs to buy
    uint256[] tokensBoughtAmounts; // Amount of token to buy for each ID
    uint256[] expectedTiers;       // Tiers the user is expecting to buy at
  }

  // Mapping variables
  mapping(uint256 => bool) internal isPurchasable;  // Whether a token ID can be purchased or not

  // Variables
  uint256 internal floorPrice;     // Base, most discounted price
  uint256 internal tierSize;       // How many asset need to be purchased to move to next discount tier
  uint256 internal priceIncrement; // Discount you get when you move up a discount step

  /***********************************|
  |               Events              |
  |__________________________________*/

  event AssetsPurchased(address indexed recipient, uint256[] tokensBoughtIds, uint256[] tokensBoughtAmounts, uint256 totalCost);
  event IDsRegistration(uint256[] ids);
  event IDsDeregistration(uint256[] ids);

  /***********************************|
  |            Constructor            |
  |__________________________________*/

  /**
   * @notice Create factory, link factory manager and store initial paramters
   * @param _factoryManagerAddr  The address of the Skyweaver Factory Manager contract
   * @param _arcadeumCoinAddr    The address of the ERC-1155 Base Token
   * @param _arcadeumCoinID      The ID of the ERC-1155 Base Token
   * @param _floorPrice          Base, most discounted price
   * @param _tierSize            How many asset need to be purchased to move to next discount tier
   * @param _priceIncrement       Discount you get when you move up a discount step
   */
  constructor(
    address _factoryManagerAddr,
    address _arcadeumCoinAddr,
    uint256 _arcadeumCoinID,
    uint256 _floorPrice,
    uint256 _tierSize,
    uint256 _priceIncrement
  ) public {

    //Input validation
    require(
      _factoryManagerAddr != address(0) &&
      _arcadeumCoinAddr != address(0) &&
      _floorPrice > 100000000 && //Sanity check to "make sure" decimals are accounted for
      _tierSize > 0 &&
      _priceIncrement > 0,
      "EternalHeroesFactory#constructor: INVALID_INPUT"
    );

    // Set variables and constants
    factoryManager = ISWSupplyManager(_factoryManagerAddr);
    arcadeumCoin = IERC1155(_arcadeumCoinAddr);
    arcadeumCoinID = _arcadeumCoinID;
    floorPrice = _floorPrice;
    tierSize = _tierSize;
    priceIncrement = _priceIncrement;
  }

  /***********************************|
  |         Management Methods        |
  |__________________________________*/

  /**
   * @notice Will indicate that asset ids in _ids are purchasable
   * @dev This contract assumes that there is a supply cap, which
   *      if present, will enable total_supply tracking. To prevent
   *      errors, a maxSupply must be set before an ID can be registered.
   * @param _ids Array of asset IDs to allow for purchasing
   */
  function registerIDs(uint256[] calldata _ids) external onlyOwner() {
    uint256[] memory maxSupplies = factoryManager.getMaxSupplies(_ids);
    for (uint256 i = 0; i < _ids.length; i++) {
      require(maxSupplies[i] > 0, "EternalHeroesFactory#registerIDs: UNCAPPED_SUPPLY");
      isPurchasable[_ids[i]] = true;
    }
    emit IDsRegistration(_ids);
  }

  /**
   * @notice Will indicate that asset ids in _ids are NOT purchasable
   * @param _ids Array of card IDs to make non-purchasable
   */
  function deregisterIDs(uint256[] calldata _ids) external onlyOwner() {
    for (uint256 i = 0; i < _ids.length; i++) {
      isPurchasable[_ids[i]] = false;
    }
    emit IDsDeregistration(_ids);
  }

  /**
   * @notice Send current ARC balance of sale contract to owner of the contract
   * @param _recipient Address where the currency will be sent to
   */
  function withdraw(address _recipient) external onlyOwner() {
    require(_recipient != address(0x0), "EternalHeroesFactory#withdraw: INVALID_RECIPIENT");
    uint256 thisBalance = arcadeumCoin.balanceOf(address(this), arcadeumCoinID);
    arcadeumCoin.safeTransferFrom(address(this), _recipient, arcadeumCoinID, thisBalance, "");
  }


  /***********************************|
  |      Receiver Method Handler      |
  |__________________________________*/

  // On receive success messages
  bytes4 constant internal ERC1155_RECEIVED_VALUE = 0xf23a6e61;
  bytes4 constant internal ERC1155_BATCH_RECEIVED_VALUE = 0xbc197c81;

  /**
   * @notice Prevents receiving Ether or calls to unsuported methods
   */
  function () external {
    revert("UNSUPPORTED_METHOD");
  }

  /**
   * @notice Handle which method is being called on transfer
   * @dev `_data` must be encoded as follow: abi.encode(Order)
   * @param _from     The address which previously owned the Token
   * @param _id       Arcadeum coin ID
   * @param _amount   Amount of Arcadeun Coin received
   * @param _data     Encoded Order structure
   * @return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")
   */
  function onERC1155Received(address, address _from, uint256 _id, uint256 _amount, bytes memory _data)
    public returns(bytes4)
  {
    // Tokens received need to be Token contract
    require(msg.sender == address(arcadeumCoin), "EternalHeroesFactory#onERC1155Received: INVALID_ARC_ADDRESS");
    require(_id == arcadeumCoinID, "EternalHeroesFactory#onERC1155Received: INVALID_ARC_ID");

    // Decode Order from _data to call _baseToToken()
    Order memory order = abi.decode(_data, (Order));
    address recipient = order.recipient == address(0x0) ? _from : order.recipient;
    _buy(order.tokensBoughtIDs, order.tokensBoughtAmounts, order.expectedTiers, _amount, recipient);

    return ERC1155_RECEIVED_VALUE;
  }

  /**
   * @dev Will pass array to `onERC1155Received()`
   */
  function onERC1155BatchReceived(
    address _operator,
    address _from,
    uint256[] memory _ids,
    uint256[] memory _amounts,
    bytes memory _data)
    public returns(bytes4)
  {
    require(_ids.length == 1, "EternalHeroesFactory#onERC1155BatchReceived: INVALID_BATCH_TRANSFER");
    require(
      ERC1155_RECEIVED_VALUE == onERC1155Received(_operator, _from, _ids[0], _amounts[0], _data),
      "EternalHeroesFactory#onERC1155BatchReceived: INVALID_ONRECEIVED_MESSAGE"
    );

    return ERC1155_BATCH_RECEIVED_VALUE;
  }


  /***********************************|
  |         Purchase Function         |
  |__________________________________*/

  /**
   * @notice Convert Base Tokens to Tokens _id and transfers Tokens to recipient.
   * @dev Assumes that all trades will be successful, or revert the whole tx
   * @param _ids           Array of Tokens ID that are bought (needs to be sorted, no duplicates)
   * @param _amounts       Amount of Tokens id bought for each corresponding Token id in _tokenIds
   * @param _expectedTiers Pirce tiers the user is expecting to buy at for each asset ID
   * @param _arcAmount     Amount of ARC sent with the purchase
   * @param _recipient     The address that receives output Tokens.
   */
  function _buy(
    uint256[] memory _ids,
    uint256[] memory _amounts,
    uint256[] memory _expectedTiers,
    uint256 _arcAmount,
    address _recipient)
    internal
  {
    // Input validation
    uint256 nTokens = _ids.length;
    uint256 tier_size = tierSize;

    // Load tokens to purchase supplies
    uint256[] memory current_supplies = factoryManager.getCurrentSupplies(_ids);

    // Total amount of card to purchase
    uint256 total_cost = 0;

    // Keep track of amount for each hero the user actually purchases.
    // While less efficient in case of amounts reduced to 0,
    // it keeps the code simpler.
    uint256[] memory amounts_to_mint = new uint256[](nTokens);

    // Validate purchase and count # of cards to purchase
    for (uint256 i = 0; i < nTokens; i++) {
      uint256 id = _ids[i];
      uint256 supply = current_supplies[i];
      uint256 to_mint = 0;
      uint256 amount = _amounts[i];

      // Validate token id
      require(isPurchasable[id], "EternalHeroesFactory#_buy: ID_NOT_PURCHASABLE");

      // Assumes IDs are sorted to make sure there are no duplicates.
      // Otherwise we would have to query supplies for each loop
      if (i > 0) {
        require(_ids[i-1] < id, "EternalHeroesFactory#_buy: UNSORTED_OR_DUPLICATE_TOKEN_IDS");
      }

      // Current discount step (division round down)
      uint256 current_tier = supply.div(tier_size);

      // Skip asset if tier is not the one expected, to not make the order fail
      if (_expectedTiers[i] != current_tier) {
        amounts_to_mint[i] = 0; // Set amount to mint for this hero to 0 and ignore in total_cost
        continue;
      }

      // Get price for given tier
      uint256 current_price = floorPrice.add(current_tier.mul(priceIncrement));

      // How many left in current tier (remainers is what is available)
      uint256 amount_left = tier_size.sub(supply.mod(tier_size));

      // Amount of assets that user will purchase
      to_mint = amount < amount_left ? amount : amount_left;

      // Increase total cost
      total_cost = total_cost.add(to_mint.mul(current_price));
      amounts_to_mint[i] = to_mint;
    }

    // Check if enough ARC was sent and refund exceeding amount
    // .sub() will revert if insufficient amount received for purchase
    // SWC-107-Reentrancy: L279-285
    uint256 refundAmount = _arcAmount.sub(total_cost);
    if (refundAmount > 0) {
      arcadeumCoin.safeTransferFrom(address(this), _recipient, arcadeumCoinID, refundAmount, "");
    }

    // Mint tokens to recipient
    factoryManager.batchMint(_recipient, _ids, amounts_to_mint, "");

    // Emit event
    emit AssetsPurchased(_recipient, _ids, amounts_to_mint, total_cost);
  }


  /***********************************|
  |         Getter Functions          |
  |__________________________________*/

  /**
   * @notice Get the purchasable status of card IDs provided
   * @param _ids Array containing the assets IDs
   * @return The purchasable status of card IDs provided
   */
  function getPurchasableStatus(uint256[] calldata _ids) external view returns (bool[] memory) {
    uint256 nIds = _ids.length;
    bool[] memory purchasableStatus = new bool[](nIds);

    // Iterate over each owner and token ID
    for (uint256 i = 0; i < nIds; i++) {
      purchasableStatus[i] = isPurchasable[_ids[i]];
    }

    return purchasableStatus;
  }

  /**
   * @notice Returns the address of the factory manager contract
   */
  function getFactoryManager() external view returns (address) {
    return address(factoryManager);
  }

  /**
   * @notice Returns the address of the Arcadeun Coin contract
   */
  function getArcadeumCoin() external view returns (address) {
    return address(arcadeumCoin);
  }

  /**
   * @notice Returns the token ID of Arcadeum Coin
   */
  function getArcadeumCoinID() external view returns (uint256) {
    return arcadeumCoinID;
  }

  /**
   * @notice Returns the current price of tokens in _ids
   * @param _ids Array containing the assets IDs
   */
  function getPrices(uint256[] calldata _ids) external view returns (uint256[] memory) {
    uint256[] memory current_prices = new uint256[](_ids.length);
    uint256[] memory current_supplies = factoryManager.getCurrentSupplies(_ids);
    for (uint256 i = 0;  i < _ids.length; i++) {
      uint256 current_tier = current_supplies[i].div(tierSize);
      current_prices[i] = floorPrice.add(current_tier.mul(priceIncrement));
    }
    return current_prices;
  }

  /**
   * @notice Returns the current price tiers of tokens in _ids
   * @param _ids Array containing the assets IDs
   */
  function getPriceTiers(uint256[] calldata _ids) external view returns (uint256[] memory) {
    uint256[] memory current_tiers = new uint256[](_ids.length);
    uint256[] memory current_supplies = factoryManager.getCurrentSupplies(_ids);
    for (uint256 i = 0;  i < _ids.length; i++) {
      current_tiers[i] = current_supplies[i].div(tierSize);
    }
    return current_tiers;
  }

  /**
   * @notice Returns how many tokens left are in each tiers for given _ids
   * @param _ids Array containing the assets IDs
   * @return Supply left in current tier for each ID and tier number
   */
  function getSuppliesCurrentTier(uint256[] calldata _ids) external view returns (uint256[] memory tiers, uint256[] memory supplies) {
    tiers = new uint256[](_ids.length);
    supplies = new uint256[](_ids.length);

    // Load supplies and tierSize
    uint256[] memory current_supplies = factoryManager.getCurrentSupplies(_ids);
    uint256 tier_size = tierSize;

    // Get current tiers and asset left per tier
    for (uint256 i = 0;  i < _ids.length; i++) {
      tiers[i] = current_supplies[i].div(tier_size);
      supplies[i] = tier_size.sub(current_supplies[i].mod(tier_size));
    }
    return (tiers, supplies);
  }

  /**
   * @notice Returns the floor price
   */
  function getFloorPrice() external view returns (uint256) {
    return floorPrice;
  }

  /**
   * @notice Returns amount of token per price tier
   */
  function getTierSize() external view returns (uint256) {
    return tierSize;
  }

  /**
   * @notice Returns how much the price increase every tier increment
   */
  function getPriceIncrement() external view returns (uint256) {
    return priceIncrement;
  }


  /***********************************|
  |         Utility Functions         |
  |__________________________________*/

  /**
   * @notice Indicates whether a contract implements the `ERC1155TokenReceiver` functions and so can accept ERC1155 token types.
   * @param  interfaceID The ERC-165 interface ID that is queried for support.s
   * @dev This function MUST return true if it implements the ERC1155TokenReceiver interface and ERC-165 interface.
   *      This function MUST NOT consume more than 5,000 gas.
   * @return Wheter ERC-165 or ERC1155TokenReceiver interfaces are supported.
   */
  function supportsInterface(bytes4 interfaceID) external view returns (bool) {
    return  interfaceID == 0x01ffc9a7 || // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
      interfaceID == 0x4e2312e0;         // ERC-1155 `ERC1155TokenReceiver` support (i.e. `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")) ^ bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`).
  }

}
