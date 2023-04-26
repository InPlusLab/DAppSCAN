pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../utils/Ownable.sol";
import "../interfaces/ISWSupplyManager.sol";
import "multi-token-standard/contracts/interfaces/IERC1155.sol";
import "multi-token-standard/contracts/utils/SafeMath.sol";

/**
 * This is a contract allowing users to mint Skyweaver's silver card
 * at a common price.
 */
contract SilverCardsFactory is Ownable {
  using SafeMath for uint256;

  /***********************************|
  |        Variables && Events        |
  |__________________________________*/

  // Constants
  uint256 constant internal decimals = 2; // Number of decimals

  // Initiate Variables
  ISWSupplyManager internal factoryManager;  // SkyWeaver Asset contract
  IERC1155 internal arcadeumCoin;            // ERC-1155 Arcadeum Coin contract
  uint256 internal arcadeumCoinID;           // ID of ARC token in respective ERC-1155 contract
  uint256 internal cardPrice;                // Price per Silver Card

  // OnReceive Objects
  struct Order {
    address recipient;             // Who receives the tokens
    uint256[] tokensBoughtIDs;     // Token IDs to buy
    uint256[] tokensBoughtAmounts; // Amount of token to buy for each ID
  }

  // Mapping variables
  mapping(uint256 => bool) internal isPurchasable;  // Whether a token ID can be purchased or not

  /***********************************|
  |               Events              |
  |__________________________________*/

  event CardsPurchased(address indexed recipient, uint256[] tokensBoughtIds, uint256[] tokensBoughtAmounts, uint256 totalCost);
  event CardPriceChange(uint256 oldPrice, uint256 newPrice);
  event IDsRegistration(uint256[] ids);
  event IDsDeregistration(uint256[] ids);


  /***********************************|
  |            Constructor            |
  |__________________________________*/

  /**
   * @notice Create factory, link factory manager and store initial paramters
   * @dev The _cardPrice should be per fraction of a card
   * @param _factoryManagerAddr The address of the Skyweaver Factory Manager contract
   * @param _arcadeumCoinAddr   The address of the ERC-1155 Base Token
   * @param _arcadeumCoinID     The ID of the ERC-1155 Base Token
   * @param _cardPrice          Price for each card
   */
  constructor(
    address _factoryManagerAddr,
    address _arcadeumCoinAddr,
    uint256 _arcadeumCoinID,
    uint256 _cardPrice
  ) public {

    //Input validation
    require(
      _factoryManagerAddr != address(0) &&
      _arcadeumCoinAddr != address(0) &&
      _cardPrice > 100000000, //Sanity check to "make sure" decimals are accounted for
      "SilverCardsFactory#constructor: INVALID_INPUT"
    );

    // Set variables and constants
    factoryManager = ISWSupplyManager(_factoryManagerAddr);
    arcadeumCoin = IERC1155(_arcadeumCoinAddr);
    arcadeumCoinID = _arcadeumCoinID;
    cardPrice = _cardPrice;
    emit CardPriceChange(0, _cardPrice);
  }


  /***********************************|
  |         Management Methods        |
  |__________________________________*/

  /**
   * @notice Will indicate that asset ids in _ids are purchasable
   * @param _ids Array of asset IDs to allow for purchasing
   * @dev Next version should pack isPurchasable to reduce SLOADs cost
   *      for bulk purchases
   */
  function registerIDs(uint256[] calldata _ids) external onlyOwner() {
    for (uint256 i = 0; i < _ids.length; i++) {
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
   * @notice Will update the card price
   * @dev Don't forget to account for the decimals
   * @param _newPrice New card price
   */
  function updateCardPrice(uint256 _newPrice) external onlyOwner() {
    // Sanity check to "make sure" decimals are accounted for (18 decimals)
    require(_newPrice > 100000000, "SilverCardsFactory#updateCardPrice: INVALID_PRICE");
    emit CardPriceChange(cardPrice, _newPrice);
    cardPrice = _newPrice;
  }

  /**
   * @notice Send current ARC balance of sale contract to owner of the contract
   * @param _recipient Address where the currency will be sent to
   */
  function withdraw(address _recipient) external onlyOwner() {
    require(_recipient != address(0x0), "SilverCardsFactory#withdraw: INVALID_RECIPIENT");
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
    require(msg.sender == address(arcadeumCoin), "SilverCardsFactory#onERC1155Received: INVALID_ARC_ADDRESS");
    require(_id == arcadeumCoinID, "SilverCardsFactory#onERC1155Received: INVALID_ARC_ID");

    // Decode Order from _data to call _buy()
    Order memory order = abi.decode(_data, (Order));
    address recipient = order.recipient == address(0x0) ? _from : order.recipient;
    _buy(order.tokensBoughtIDs, order.tokensBoughtAmounts, _amount, recipient);

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
    require(_ids.length == 1, "SilverCardsFactory#onERC1155BatchReceived: INVALID_BATCH_TRANSFER");
    require(
      ERC1155_RECEIVED_VALUE == onERC1155Received(_operator, _from, _ids[0], _amounts[0], _data),
      "SilverCardsFactory#onERC1155BatchReceived: INVALID_ONRECEIVED_MESSAGE"
    );

    return ERC1155_BATCH_RECEIVED_VALUE;
  }


  /***********************************|
  |         Purchase Function         |
  |__________________________________*/

  /**
   * @notice Convert Base Tokens to Tokens _id and transfers Tokens to recipient.
   * @dev Assumes that all trades will be successful, or revert the whole tx
   * @param _ids         Array of Tokens ID that are bought
   * @param _amounts     Amount of Tokens id bought for each corresponding Token id in _tokenIds
   * @param _arcAmount   Amount of ARC sent with the purchase
   * @param _recipient   The address that receives output Tokens.
   */
  function _buy(
    uint256[] memory _ids,
    uint256[] memory _amounts,
    uint256 _arcAmount,
    address _recipient)
    internal
  {
    // Input validation
    uint256 nTokens = _ids.length;

    // Total amount of card to purchase
    uint256 total_quantity = 0;

    // Validate purchase and count # of cards to purchase
    for (uint256 i = 0; i < nTokens; i++) {
      // Validate token id
      require(isPurchasable[_ids[i]], "SilverCardsFactory#_buy: ID_NOT_PURCHASABLE");

      // Increment cost
      total_quantity = total_quantity.add(_amounts[i]);
    }

    // Calculate purchase cost
    uint256 total_cost = total_quantity.mul(cardPrice);

    // Check if enough ARC was sent and refund exceeding amount
    uint256 refundAmount = _arcAmount.sub(total_cost); // Will throw if insufficient amount received
    if (refundAmount > 0) {
      arcadeumCoin.safeTransferFrom(address(this), _recipient, arcadeumCoinID, refundAmount, "");
    }

    // Mint tokens to recipient
    factoryManager.batchMint(_recipient, _ids, _amounts, "");

    // Emit event
    emit CardsPurchased(_recipient, _ids, _amounts, total_cost);
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
   * @notice Returns the current silver cards price
   */
  function getCardPrice() external view returns (uint256) {
    return cardPrice;
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
