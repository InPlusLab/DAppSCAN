pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "../utils/Ownable.sol";
import "../interfaces/ISkyweaverAssets.sol";
import "multi-token-standard/contracts/utils/SafeMath.sol";

/**
 * This is a contract allowing users to mint random Skyweaver's
 * gold cards for a given weave amount using a future block hash commit scheme.
 */
contract GoldCardsFactory is Ownable {
  using SafeMath for uint256;

  /***********************************|
  |        Variables && Events        |
  |__________________________________*/

  // Constants
  uint256 constant internal decimals = 2; // Number of decimals

  // Initiate Variables
  ISkyweaverAssets internal skyweaverAssets; // ERC-1155 Skyweaver assets contract
  ISkyweaverAssets internal weaveContract;   // ERC-1155 Weave contract
  uint256 internal weaveID;                  // ID of Weave token in respective ERC-1155 contract
  uint256 internal goldPrice;                // Price per Gold Card in weave, ignoring decimals
  uint256 internal goldRefund;               // Amount of weave to receive when melting a gold card, ignoring decimals
  uint256 internal rngDelay;                 // Amount of blocks after commit before one can mint gold cards

  // OnReceive Objects
  struct GoldOrder {
    address cardRecipient;  // Who receives the tokens
    address feeRecipient;   // Who will receive the minting fee, if any
    uint256 cardAmount;     // Amount of gold cards to buy, ignoring decimals
    uint256 feeAmount;      // Amount of weave sent for minting fee, if any
    uint256 rngBlock;       // Block # to use for RNG
  }

  // Mapping variables
  mapping(uint256 => bool) internal isPurchasable; // Whether a token ID can be purchased or not
  mapping(bytes32 => bool) internal orderStatus;   // 0: Non-existant or executed, 1: Pending
  uint256[] internal cardsPool;                    // Array containing all card ids registered

  /***********************************|
  |               Events              |
  |__________________________________*/

  event OrderCommited(GoldOrder order);
  event OrderRecommitted(GoldOrder order);
  event OrderFulfilled(bytes32 orderHash);
  event GoldPriceChanged(uint256 oldPrice, uint256 newPrice);
  event GoldRefundChanged(uint256 oldRefund, uint256 newRefund);
  event RNGDelayChanged(uint256 oldDelay, uint256 newDelay);
  event IDsRegistration(uint256[] ids);
  event IDsDeregistration(uint256[] ids);

  /***********************************|
  |            Constructor            |
  |__________________________________*/

  /**
   * @notice Create factory, link factory manager and store initial paramters
   * @param _assetsAddr  The address of the ERC-1155 Assets Token
   * @param _weaveAddr   The address of the ERC-1155 Base Token
   * @param _weaveID     The ID of the ERC-1155 Base Token
   * @param _goldPrice   Price for each card
   * @param _goldRefund  Amount of weave to receive when melting a gold card
   * @param _rngDelay    Amount of blocks after commit before one can mint cards
   */
  constructor(
    address _assetsAddr,
    address _weaveAddr,
    uint256 _weaveID,
    uint256 _goldPrice,
    uint256 _goldRefund,
    uint256 _rngDelay
  ) public {

    //Input validation
    require(
      _assetsAddr != address(0) &&
      _weaveAddr != address(0) &&
      _goldPrice > 100000000   && // Sanity check to "make sure" decimals are accounted for
      _goldPrice >= goldRefund && // Sanity check
      _rngDelay > 0,
      "GoldCardsFactory#constructor: INVALID_INPUT"
    );

    // Set variables and constants
    skyweaverAssets = ISkyweaverAssets(_assetsAddr);
    weaveContract = ISkyweaverAssets(_weaveAddr);
    weaveID = _weaveID;
    goldPrice = _goldPrice;
    goldRefund = _goldRefund;
    rngDelay = _rngDelay;

    emit GoldPriceChanged(0, _goldPrice);
  }


  /***********************************|
  |         Management Methods        |
  |__________________________________*/

  /**
   * @notice Will indicate that asset ids in _ids are purchasable & add them to card pool
   * @dev Will throw if an ID is already registered to prevent duplicates
   *      in cardPool array.
   * @param _ids Array of asset IDs to allow for purchasing
   */
  function registerIDs(uint256[] calldata _ids) external onlyOwner() {
    for (uint256 i = 0; i < _ids.length; i++) {
      uint256 id = _ids[i];
      require(isPurchasable[id] == false, "GoldCardsFactory#registerIDs: ID_ALREADY_REGISTERED");
      isPurchasable[id] = true;
      cardsPool.push(id);
    }
    emit IDsRegistration(_ids);
  }

  /**
   * @notice Will indicate that asset ids in _ids are NOT mintable
   * @dev Need to account for the fact that the array will change
   *      as ids are removed, so the corresponding indexes will change
   *      as well. Using decending order makes it easier.
   * @param _ids             Array of card IDs to make non-purchasable
   * @param _cardPoolIndexes The cardPools index for each id in _ids
   */
  function deregisterIDs(uint256[] calldata _ids, uint256[] calldata _cardPoolIndexes) external onlyOwner() {
    for (uint256 i = 0; i < _ids.length; i++) {
      uint256 id = _ids[i];
      uint256 card_pool_index = _cardPoolIndexes[i];

      // Check if valid deregistration
      require(isPurchasable[id] == true, "GoldCardsFactory#deregisterIDs: ID_NOT_REGISTERED");
      require(cardsPool[card_pool_index] == id, "GoldCardsFactory#deregisterIDs: INVALID_CARD_POOL_INDEX");

      // Set`isPurchasable` to false.
      isPurchasable[_ids[i]] = false;

      // Overwrite id with last value in array and delete last element
      if (card_pool_index < cardsPool.length-1) {
        cardsPool[card_pool_index] = cardsPool[cardsPool.length-1];
      }
      cardsPool.length--; // Use .pop() for solc >= 0.6.0
    }
    emit IDsDeregistration(_ids);
  }

  /**
   * @notice Will update the card price
   * @dev Don't forget to account for currency's decimals
   * @dev Does not account for card decimals
   * @param _newPrice New card price
   */
  function updateGoldPrice(uint256 _newPrice) external onlyOwner() {
    // Sanity check to "make sure" decimals are accounted for (18 decimals)
    require(_newPrice > 100000000, "GoldCardsFactory#updateGoldPrice: INVALID_PRICE");
    require(_newPrice >= goldRefund, "GoldCardsFactory#updateGoldPrice: PRICE_HIGHER_THAN_REFUND");
    emit GoldPriceChanged(goldPrice, _newPrice);
    goldPrice = _newPrice;
  }

  /**
   * @notice Will update the card refund amount
   * @dev Don't forget to account for the currency's decimals
   @ @dev Should ignore card's decimals
   * @param _newRefund New card refund amount
   */
  function updateGoldRefund(uint256 _newRefund) external onlyOwner() {
    require(goldPrice >= _newRefund, "GoldCardsFactory#updateGoldRefund: PRICE_HIGHER_THAN_REFUND");
    emit GoldRefundChanged(goldRefund, _newRefund);
    goldRefund = _newRefund;
  }

  /**
   * @notice Will update the rng delay amount
   * @param _newDelay New rng block delay
   */
  function updateRNGDelay(uint256 _newDelay) external onlyOwner() {
    require(_newDelay > 0, "GoldCardsFactory#updateRNGDelay: INVALID_DELAY");
    emit RNGDelayChanged(rngDelay, _newDelay);
    rngDelay = _newDelay;
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
   * @dev Will pass array to `onERC1155BatchReceived()`
   */
  function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _amount, bytes memory _data)
    public returns(bytes4)
  {
    // Create arrays to pass to onERC1155BatchReceived()
    uint256[] memory ids = new uint256[](1);
    uint256[] memory amounts = new uint256[](1);
    ids[0] = _id;
    amounts[0] = _amount;

    // call onERC1155BatchReceived()
    require(
      ERC1155_BATCH_RECEIVED_VALUE == onERC1155BatchReceived(_operator, _from, ids, amounts, _data),
      "NiftyswapExchange#onERC1155Received: INVALID_ONRECEIVED_MESSAGE"
    );

    return ERC1155_RECEIVED_VALUE;
  }

  /**
   * @notice Handle which method is being called on transfer
   * @dev `_data` must be encoded as follow: abi.encode(BuyCardsObj)
   * @param _from     The address which previously owned the Tokens
   * @param _ids      An array containing ids of each Token being transferred
   * @param _amounts  An array containing amounts of each Token being transferred
   * @param _data     Encoded GoldOrder structure or recipient address if melting
   * @return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")
   */
  function onERC1155BatchReceived(
    address, // _operator
    address _from,
    uint256[] memory _ids,
    uint256[] memory _amounts,
    bytes memory _data)
    public returns(bytes4)
  {
    // Commit for gold card creation
    if (msg.sender == address(weaveContract)) {
      require(_ids.length == 1, "GoldCardsFactory#onERC1155BatchReceived: INVALID_ARRAYS");
      require(_ids[0] == weaveID, "GoldCardsFactory#onERC1155BatchReceived: INVALID_WEAVE_ID");

      // Decode GoldOrder from _data to call _commit()
      GoldOrder memory obj = abi.decode(_data, (GoldOrder));
      _commit(_amounts[0], obj);

    // Gold cards to melt back into weave
    } else if (msg.sender == address(skyweaverAssets)) {

      // If recipient is specified in _data, decode and use that
      address recipient = _data.length == 32 ? abi.decode(_data, (address)) : _from;
      _melt(_ids, _amounts, recipient);

    } else {
      revert("GoldCardsFactory#onERC1155BatchReceived: INVALID_TOKEN");
    }

    return ERC1155_BATCH_RECEIVED_VALUE;
  }


  /***********************************|
  |         Minting Functions         |
  |__________________________________*/

  /**
   * @notice Commits weave for gold cards minting
   * @param _weaveAmount  Amount of weave sent with the commit
   * @param _order      GoldOrder object
   *
   */
  function _commit(uint256 _weaveAmount, GoldOrder memory _order)
    internal
  {
    // Check if weave sent is sufficient for order
    uint256 total_cost = _order.cardAmount.mul(goldPrice).add(_order.feeAmount);
    uint256 refund_amount = _weaveAmount.sub(total_cost); // Will throw if insufficient amount received

    // Set RNG block
    _order.rngBlock = block.number.add(rngDelay);

    // Mark order as pending
    bytes32 order_hash = keccak256(abi.encode(_order));
    require(!orderStatus[order_hash], "GoldCardsFactory#_commit: ORDER_HASH_ALREADY_USED");
    orderStatus[order_hash] = true;

    // Check if more than enough weave was sent, refund exceeding amount
    if (refund_amount > 0) {
      weaveContract.safeTransferFrom(address(this), _order.cardRecipient, weaveID, refund_amount, "");
    }

    // Emit event
    emit OrderCommited(_order);
  }

  /**
   * @notice Recommit to future block for RNG if order wasn't executed in time
   * @dev Can only be executed if an order is not executable anymore.
   * @param _order GoldOrder object associated with the given order to recommit
   */
  function recommit(GoldOrder memory _order)
    public
  {
    bytes32 old_order_hash = keccak256(abi.encode(_order));

    // Get status of old order (1: pending)
    bool old_order_status = orderStatus[old_order_hash];

    // Check if order exists and hasn't been executed yet
    require(old_order_status, "GoldCardsFactory#recommit: ORDER_NON_EXISTANT_OR_EXECUTED");
    require(block.number.sub(_order.rngBlock) > 256, "GoldCardsFactory#recommit: ORDER_NOT_EXPIRED");

    // Set new RNG block in order
    // new_rng_block > _rngBlock as per previous require statement
    _order.rngBlock = block.number.add(rngDelay);

    // Get hash of the new order with new rngBlock
    bytes32 new_order_hash = keccak256(abi.encode(_order));

    // Delete old order
    orderStatus[old_order_hash] = false;

    // Store new hash
    require(!orderStatus[new_order_hash], "GoldCardsFactory#recommit: ORDER_HASH_ALREADY_USED");
    orderStatus[new_order_hash] = true;

    // Emit event
    emit OrderRecommitted(_order);
  }

  /**
   * @notice Commits weave for gold cards minting
   * @dev The ids to mint for a given order are generated and sorted off-chain
   *      but their validity is verified on-chain before being minted.
   * @param _order    GoldOrder object associated with the given order
   * @param _ids      Sorted array of ids to mint
   * @param _indexes  Array containing _ids indexes, ordered by the
   *                  sequence in which they appear in the rng function.
   */
  function mineGolds(GoldOrder calldata _order, uint256[] calldata _ids, uint256[] calldata _indexes)
    external
  {
    // Check if the total amount of token to mint correspond to array provided
    require(_order.cardAmount == _indexes.length, "GoldCardsFactory#mineGolds: INVALID_INDEXES_ARRAY_LENGTH");

    // If rngBlock is current block or block older than 256 ago, the rng_seed will be deterministic (blockhash will return 0x).
    require(block.number.sub(_order.rngBlock.add(1)) <= 255, "GoldCardsFactory#mineGolds: RNG_BLOCK_OUT_OF_RANGE");

    // Compute the order hash
    bytes32 order_hash = keccak256(abi.encode(_order));

    // Check whether the order exists or was already executed
    require(orderStatus[order_hash], "GoldCardsFactory#mineGolds: ORDER_NON_EXISTANT_OR_EXECUTED");

    // Mark the order as executed (and clean storage)
    orderStatus[order_hash] = false;

    // Get RNG seed
    bytes32 rng_seed = keccak256(
      abi.encode(
        order_hash, // change to order_hash
        blockhash(_order.rngBlock) //Should NEVER be 0x0
      )
    );

    // Get random cards
    uint256[] memory amounts = validateRandomCards(rng_seed, _ids, _indexes);

    // Burn the non-refundable weave
    uint256 weave_to_burn = (_order.cardAmount.mul(goldPrice)).sub(_order.cardAmount.mul(goldRefund));
    weaveContract.burn(weaveID, weave_to_burn);

    // Mint gold cards
    skyweaverAssets.batchMint(_order.cardRecipient, _ids, amounts, "");

    // Pay fee to operator
    uint256 fee_amount = _order.feeAmount;
    if (fee_amount > 0) {
      // If send to `feeRecipient` if specified, else free for all
      address fee_recipient = _order.feeRecipient == address(0x0) ? msg.sender : _order.feeRecipient;
      weaveContract.safeTransferFrom(address(this), fee_recipient, weaveID, fee_amount, "");
    }

    // Emit event
    emit OrderFulfilled(order_hash);
  }


  /***********************************|
  |          Melting Function         |
  |__________________________________*/

  /**
   * @notice Commits weave for gold cards minting
   * @dev Sending fractions of card will not provide any refund (rounded down)
   * @param _ids       Array of Gol cards that will be melted
   * @param _amounts   Amount of Tokens id bought for each corresponding Token id in _tokenIds
   * @param _recipient Which address will receive the weave
   *
   * todo ; check if tokens received are gold cards and not silvers!
   */
  function _melt(uint256[] memory _ids, uint256[] memory _amounts, address _recipient)
    internal
  {
    // Amount to refund
    uint256 n_burns = 0;

    // Burn gold cards
    skyweaverAssets.batchBurn(_ids, _amounts);

    // Calculate refund
    for (uint256 i = 0; i < _ids.length; i++) {
      n_burns = n_burns.add(_amounts[i] / 10**decimals); //Removing card decimals
    }

    // Send refund
    weaveContract.safeTransferFrom(address(this), _recipient, weaveID, n_burns.mul(goldRefund), "");
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

    // Iterate over each token id
    for (uint256 i = 0; i < nIds; i++) {
      purchasableStatus[i] = isPurchasable[_ids[i]];
    }

    return purchasableStatus;
  }

  /**
   * @notice Get the order status for a an array of orders
   * @param _orderHashes Array containing the orders hashes
   * @return Status of the corresponding orders, where F is non-existant or executed and T is pending.
   */
  function getOrderStatuses(bytes32[] calldata _orderHashes) external view returns (bool[] memory) {
    uint256 nOrders = _orderHashes.length;
    bool[] memory order_statuses = new bool[](nOrders);

    // Iterate over order hashes
    for (uint256 i = 0; i < nOrders; i++) {
      order_statuses[i] = orderStatus[_orderHashes[i]];
    }

    return order_statuses;
  }

  /**
   * @notice Returns the RNG seed for a given block # and given address
   * @param _order Order to get the RNG seed of
   * @return rng seed for a given order
   */
  function getRNGSeed(GoldOrder calldata _order) external view returns (bytes32 rng_seed) {
    return keccak256(
      abi.encode(
        keccak256(abi.encode(_order)),
        blockhash(_order.rngBlock)
      )
    );
  }

  /**
   * @notice Returns the array containing all ids registered
   */
  function getCardPool() external view returns (uint256[] memory) {
    return cardsPool;
  }

  /**
   * @notice Returns the address of the factory manager contract
   */
  function getFactoryManager() external view returns (address) {
    return address(skyweaverAssets);
  }

  /**
   * @notice Returns the address of the Arcadeun Coin contract
   */
  function getWeave() external view returns (address) {
    return address(weaveContract);
  }

  /**
   * @notice Returns the token ID of weave
   */
  function getWeaveID() external view returns (uint256) {
    return weaveID;
  }

  /**
   * @notice Returns the current gold cards price in Weave
   */
  function getGoldPrice() external view returns (uint256) {
    return goldPrice;
  }

  /**
   * @notice Returns the current gold cards refund amount
   */
  function getGoldRefund() external view returns (uint256) {
    return goldRefund;
  }

  /**
   * @notice Returns the rng commit delay
   */
  function getRNGDelay() external view returns (uint256) {
    return rngDelay;
  }


  /***********************************|
  |         Utility Functions         |
  |__________________________________*/

  /**
   * @notice Will verify that for a given seed, the _ids array provided is correct
   * @dev The _order argument allows _ids to be sorted, which is necessary for
   *      minting the asset (enforced by supply manager).
   * @dev Using modulo for randomness can introduce a significant bias where low index
   *      cards have higher probability of being selected than others. This bias becomes
   *      less significant with larger number/modulo ratio. One can calculate the bias as
   *      ceil(k/n)/K - floor(K/n)/K, where K is the number and n is the modulo. In our
   *      case, since we use an integer field of 2**256, this bias should be negligeable.
   *      This is especially true considering the total # of gold cards will be low, hence
   *      this is an acceptable bias for uniform sampling.
   * @param _seed    Value used for RNG seed
   * @param _ids     Array of ids that will be generated from the _seed
   * @param _indexes Indexes in _ids sorted by the sequence in which they
   *                 will be generated from the random function.
   * @return Array of how many copies for each ID was present
   */
  function validateRandomCards(bytes32 _seed, uint256[] memory _ids, uint256[] memory _indexes) public returns (uint256[] memory) {
    // Amount of cards to be printed for each id
    uint256[] memory amounts = new uint256[](_ids.length);

    // Number of card ids that can be minted
    uint256 pool_size = cardsPool.length;
    uint256 rng = uint256(_seed);

    // Get random index for each gold card to mint
    for (uint256 i = 0; i < _indexes.length; i++) {

      // Index of current rng id in _ids
      uint256 idx = _indexes[i];

      // Get token ID associated with random number
      uint256 rand_id = cardsPool[rng % pool_size];

      // Check if provided ID matches id found
      require(rand_id == _ids[idx], "GoldCardsFactory#validateRandomCards: INVALID_ID");

      // Increment amount to mint for the corresponding id (could be duplicate ids)
      amounts[idx] = amounts[idx].add(10**decimals); // Adding the decimals

      // New rng
      rng = uint256(keccak256(abi.encodePacked(rng)));
    }

    return amounts;
  }

  /**
   * @notice Will return _amount random ids based on seed (unsorted and doesn't stack duplicates)
   * @dev Ids returned are unsorted and duplicates are not stacked
   * @dev See validateRandomCards() for modulo bias explaination
   * @param _seed   Value used for RNG seed
   * @param _amount Amount of random indexes to return
   * @return Array containing sampled IDs
   */
  function getRandomCards(bytes32 _seed, uint256 _amount) external view returns (uint256[] memory) {

    // Amount of cards to be printed for each id
    uint256[] memory ids = new uint256[](_amount);

    // Number of card ids that can be minted
    uint256 pool_size = cardsPool.length;
    uint256 rng = uint256(_seed);

    // Get random index for each gold card to mint
    for (uint256 i = 0; i < _amount; i++) {

      // Get token ID associated with random number
      ids[i] = cardsPool[rng % pool_size];

      // New rng
      rng = uint256(keccak256(abi.encodePacked(rng)));
    }

    return ids;
  }

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
