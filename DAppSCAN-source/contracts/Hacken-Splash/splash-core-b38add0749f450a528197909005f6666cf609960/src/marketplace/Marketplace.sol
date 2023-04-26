// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "oz-contracts/access/Ownable.sol";

import "../utils/Errors.sol";
import "../interfaces/IRegistry.sol";

/**
  Struct to hold information about a listing
  @member active:         If the listing is active
  @member rentDuration:   (If it's a rent listing) duration to be rented
  @member price:          Price of listing 
*/
struct Listing {
    bool active;
    uint48 rentDuration;
    uint256 price;
}

/**
  Struct to hold information about a listing
  @member active:         If the listing is active
  @member amount:         Amount of card to be sold
  @member cardType:       Type of the card
  @member owner:          Owner of the listing
  @member price:          Price of the listing
*/
struct CardListing {
  bool active;
  uint32 amount;
  uint32 cardType;
  address owner;
  uint256 price;
}

struct CardPrice {
  bool active;
  uint256 price;
}

/**
  @title Marketplace
  @notice Buy, sell, rent functions related to marketplace
  @notice Works with ERC721 and ERC1155 tokens
  @author Hamza Karabag
*/
contract Marketplace is Ownable {
  IRegistry registry;

  uint128 private _listingNonce = 0;
  uint128 private _commission = 2; //%

  mapping(uint256 => Listing) public idToListing;
  mapping(uint256 => CardListing) public idToCardListing;
  mapping(uint256 => CardPrice) public idToPrice;

  // To keep track of how much of one user's cards are listed
  mapping(address => mapping(uint256 => uint256)) listingCounts;

  event PlayerListed(uint256 indexed playerId);
  event PlayerPriceChange(uint256 indexed playerId);
  event PlayerListedForRent(uint256 indexed playerId);
  event PlayerSold(uint256 indexed playerId);
  event PlayerRented(uint256 indexed playerId);
  event PlayerDelisted(uint256 indexed playerId);

  event CardListed(uint32 indexed cardType, uint256 listingId);
  event CardPriceChange(uint256 listingId);
  event CardSold(uint32 indexed cardType, uint256 listingId);
  event CardDelisted(uint256 listingId);

  event CommisionChanged(uint128 newCommision);

  constructor(IRegistry registryAddress) {
    registry = IRegistry(registryAddress);
  }

  // ############## SETTERS ############## //

  /** @dev Setter for _commission */
  function setCommission(uint128 newCommission) external onlyOwner {
    _commission = newCommission;
    emit CommisionChanged(newCommission);
  }

  function setCardPrice(uint256 id, uint256 newPrice) external onlyOwner {
    idToPrice[id] = CardPrice(true, newPrice);
  }

  function unsetCardPrice(uint256 id) external onlyOwner {
    delete idToPrice[id];
  }

  // ############## LIST PLAYER ############## //

  function listPlayer(uint256 playerId, uint256 price) external {
    _listPlayer(playerId, price, 0);
  }

  function listPlayerForRent(
    uint256 playerId,
    uint256 price,
    uint48 duration
  ) external {
    _listPlayer(playerId, price, duration);
  }

  /**
    @notice Changes listing price
    @dev Emits PlayerPriceChange
  */
  function changeListingPrice(uint256 playerId, uint256 newPrice) external {
    require(idToListing[playerId].active, "Listing is not active");
    require(registry.sp721().ownerOf(playerId) == msg.sender, "Address doesn't own the player");

    idToListing[playerId].price = newPrice;
    emit PlayerPriceChange(playerId);
  }

  /**
    @notice Lists player
    @param playerId:        ID of the player
    @param price:           Price of the player
    @param rentDuration:    (If for rent) Duration to rent 
  */
  function _listPlayer(
    uint256 playerId,
    uint256 price,
    uint48 rentDuration
  ) private {
    require(!idToListing[playerId].active, "Player is already on sale");
    require(registry.sp721().ownerOf(playerId) == msg.sender, "Address doesn't own the player");

    // It'll revert instead of returning false
    registry.management().checkForSale(msg.sender, playerId);

    idToListing[playerId] = Listing({active: true, rentDuration: rentDuration, price: price});
    emit PlayerListed(playerId);
  }

  // ############## DELIST PLAYER ############## //

  /**
    @notice Delists a player, by simply deleting the Listing
    @param playerId: ID of the player
  */
  function delistPlayer(uint256 playerId) external {
    require(idToListing[playerId].active, "Player not on sale");
    require(registry.sp721().ownerOf(playerId) == msg.sender, "Address doesn't own the player");

    delete idToListing[playerId];
    emit PlayerDelisted(playerId);
  }

  // ############## LIST CARD ############## //

  /**
    @notice Lists card
    @dev One user can create different amount of cards on the market,
    that's why we had to generate listing IDs for each listing

    @dev Emits CardListed
  */
  function listCard(uint32 amount, uint32 cardType, uint256 price) external {
    require(
        registry.sp1155().isApprovedForAll(msg.sender, address(this)),
        "Marketplace not approved for listing"
    );

    uint256 availableCards = registry.sp1155().balanceOf(msg.sender, cardType) -
        listingCounts[msg.sender][cardType];

    require(availableCards >= amount, "Not enough cards to sell");

    uint256 listingId = uint256(keccak256(abi.encode(_listingNonce++)));

    idToCardListing[listingId] = CardListing({
        active: true,
        amount: amount,
        cardType: cardType,
        owner: msg.sender,
        price: price
    });

    listingCounts[msg.sender][cardType] += amount;
    emit CardListed(cardType, listingId);
  }

  /**
    @notice Changes price of the given listing ID
    @dev Emits CardPriceChange
  */
  function changeCardListingPrice(uint256 listingId, uint256 newPrice) external {
    CardListing memory cardListing = idToCardListing[listingId];
    require(cardListing.active, "Card listing is not active");
    require(cardListing.owner == msg.sender, "Address does not own the player");

    idToCardListing[listingId].price = newPrice;
    emit CardPriceChange(listingId);
  }

  // ############## DELIST CARD ############## //

  /**
    @notice Delists a player by deleting its listing
    @dev Emits CardDelisted
  */
  function delistCard(uint256 listingId) external {
    CardListing memory cardListing = idToCardListing[listingId];

    require(cardListing.active, "Card listing is not active");
    require(cardListing.owner == msg.sender, "Address does not own the player");

    listingCounts[msg.sender][cardListing.cardType] -= cardListing.amount;

    delete idToCardListing[listingId];
    emit CardDelisted(listingId);
  }

  // ############## BUY/RENT PLAYER ############## //

  /**
    @notice Buys the player with given ID
    @dev Emits PlayerSold
    @dev It is possible one to buy their own player. I don't see any harm in it
  */
  function buyPlayer(uint256 playerId) external {
    Listing memory listing = idToListing[playerId];

    require(listing.active, "Player not on sale");
    require(listing.rentDuration == 0, "Player is not for direct sale");

    // It'll revert if player is not available to buy
    // This will happen when user enters a tournament with a listed player
    registry.management().checkForBuy(msg.sender, playerId);

    address listingOwner = registry.sp721().ownerOf(playerId);
    uint256 price = listing.price;
    uint256 commissionPrice = (price * _commission) / 100;

    // Transfer price for user
    require(
        registry.sp20().transferFrom(msg.sender, address(this), price),
        "Checkout while buying failed"
    );
    // Approve deducted amount to owner
    require(
        registry.sp20().approve(listingOwner, price - commissionPrice),
        "Approve to owner failed"
    );

    registry.sp721().transferFrom(listingOwner, msg.sender, playerId);

    delete idToListing[playerId];
    emit PlayerSold(playerId);
  }

  /**
    @notice Rents player with given ID
    @dev Emits PlayerRented
    @dev It is possible one to rent their own player. I don't see any harm in it
  */
  function rentPlayer(uint256 playerId) external {
    Listing memory listing = idToListing[playerId];

    require(listing.active, "Player not on sale");
    require(listing.rentDuration > 0, "Player is not for rent");

    // It'll revert if player is not available to buy
    // This will happen when user enters a tournament with a listed player
    registry.management().checkForBuy(msg.sender, playerId);

    address listingOwner = registry.sp721().ownerOf(playerId);
    uint256 price = listing.price;
    uint256 commissionPrice = (price * _commission) / 100;

    // Transfer price for user
    require(
        registry.sp20().transferFrom(msg.sender, address(this), price),
        "Checkout while renting failed"
    );
    // Approve deducted amount to owner
    require(
        registry.sp20().approve(listingOwner, price - commissionPrice),
        "Approve to owner failed"
    );

    registry.management().rentPlayerFrom(listingOwner, msg.sender, playerId, listing.rentDuration);

    delete idToListing[playerId];
    emit PlayerRented(playerId);
  }

  // ############## BUY CARD ############## //

  /**
    @notice Buys a card with given listing ID
    @dev Emits CardSold
  */
  function buyCard(uint256 listingId) external {
    CardListing memory cardListing = idToCardListing[listingId];
    require(cardListing.active, "Listing is not active");

    uint256 commissionPrice = (cardListing.price * _commission) / 100;

    require(
        registry.sp20().transferFrom(msg.sender, address(this), cardListing.price),
        "Checkout while buying failed"
    );

    require(
        registry.sp20().approve(cardListing.owner, cardListing.price - commissionPrice),
        "Approve to owner failed"
    );

    listingCounts[cardListing.owner][cardListing.cardType] -= cardListing.amount;
    emit CardSold(cardListing.cardType, listingId);

    registry.sp1155().safeTransferFrom(
      cardListing.owner,
      msg.sender,
      cardListing.cardType,
      cardListing.amount,
      ""
    );
  }

  function buyCardFromSale(uint256 id, uint256 amount) external {

    require(idToPrice[id].active, Errors.SALE_NOT_ACTIVE);
    require(
      registry.sp20().transferFrom(msg.sender, address(this), idToPrice[id].price * amount), 
      Errors.TOKEN_CHECKOUT_FAIL
    );

    registry.sp1155().mint(msg.sender, id, amount, "");
  }
}
