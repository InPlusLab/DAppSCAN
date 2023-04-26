// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IBuyNowMarketplace {
    event ListedForBuyNow(uint256 indexed _id, uint256 _price, address _currentOwner, uint256 _startDate);
    event BuyNowPriceChanged(uint256 indexed _id, uint256 _price);
    event BuyNowDeListed(uint256 indexed _id);
    event BuyNowPurchased(uint256 indexed _tokenId, address _buyer, address _currentOwner, uint256 _price);

    function listForBuyNow(address _creator, uint256 _id, uint128 _listingPrice, uint128 _startDate) external;

    function buyEditionToken(uint256 _id) external payable;
    function buyEditionTokenFor(uint256 _id, address _recipient) external payable;

    function setBuyNowPriceListing(uint256 _editionId, uint128 _listingPrice) external;
}

interface IEditionOffersMarketplace {
    event EditionAcceptingOffer(uint256 indexed _editionId, uint128 _startDate);
    event EditionBidPlaced(uint256 indexed _editionId, address _bidder, uint256 _amount);
    event EditionBidWithdrawn(uint256 indexed _editionId, address _bidder);
    event EditionBidAccepted(uint256 indexed _editionId, uint256 indexed _tokenId, address _bidder, uint256 _amount);
    event EditionBidRejected(uint256 indexed _editionId, address _bidder, uint256 _amount);
    event EditionConvertedFromOffersToBuyItNow(uint256 _editionId, uint128 _price, uint128 _startDate);

    function enableEditionOffers(uint256 _editionId, uint128 _startDate) external;

    function placeEditionBid(uint256 _editionId) external payable;
    function placeEditionBidFor(uint256 _editionId, address _bidder) external payable;

    function withdrawEditionBid(uint256 _editionId) external;

    function rejectEditionBid(uint256 _editionId) external;

    function acceptEditionBid(uint256 _editionId, uint256 _offerPrice) external;

    function convertOffersToBuyItNow(uint256 _editionId, uint128 _listingPrice, uint128 _startDate) external;
}

interface IEditionSteppedMarketplace {
    event EditionSteppedSaleListed(uint256 indexed _editionId, uint128 _basePrice, uint128 _stepPrice, uint128 _startDate);
    event EditionSteppedSaleBuy(uint256 indexed _editionId, uint256 indexed _tokenId, address _buyer, uint256 _price, uint16 _currentStep);
    event EditionSteppedAuctionUpdated(uint256 indexed _editionId, uint128 _basePrice, uint128 _stepPrice);

    function listSteppedEditionAuction(address _creator, uint256 _editionId, uint128 _basePrice, uint128 _stepPrice, uint128 _startDate) external;

    function buyNextStep(uint256 _editionId) external payable;
    function buyNextStepFor(uint256 _editionId, address _buyer) external payable;

    function convertSteppedAuctionToListing(uint256 _editionId, uint128 _listingPrice, uint128 _startDate) external;

    function convertSteppedAuctionToOffers(uint256 _editionId, uint128 _startDate) external;

    function updateSteppedAuction(uint256 _editionId, uint128 _basePrice, uint128 _stepPrice) external;
}

interface IReserveAuctionMarketplace {
    event ListedForReserveAuction(uint256 indexed _id, uint256 _reservePrice, uint128 _startDate);
    event BidPlacedOnReserveAuction(uint256 indexed _id, address _currentOwner, address _bidder, uint256 _amount, uint256 _originalBiddingEnd, uint256 _currentBiddingEnd);
    event ReserveAuctionResulted(uint256 indexed _id, uint256 _finalPrice, address _currentOwner, address _winner, address _resulter);
    event BidWithdrawnFromReserveAuction(uint256 _id, address _bidder, uint128 _bid);
    event ReservePriceUpdated(uint256 indexed _id, uint256 _reservePrice);
    event ReserveAuctionConvertedToBuyItNow(uint256 indexed _id, uint128 _listingPrice, uint128 _startDate);
    event EmergencyBidWithdrawFromReserveAuction(uint256 indexed _id, address _bidder, uint128 _bid);

    function placeBidOnReserveAuction(uint256 _id) external payable;
    function placeBidOnReserveAuctionFor(uint256 _id, address _bidder) external payable;

    function listForReserveAuction(address _creator, uint256 _id, uint128 _reservePrice, uint128 _startDate) external;

    function resultReserveAuction(uint256 _id) external;

    function withdrawBidFromReserveAuction(uint256 _id) external;

    function updateReservePriceForReserveAuction(uint256 _id, uint128 _reservePrice) external;

    function emergencyExitBidFromReserveAuction(uint256 _id) external;
}

interface IKODAV3PrimarySaleMarketplace is IEditionSteppedMarketplace, IEditionOffersMarketplace, IBuyNowMarketplace, IReserveAuctionMarketplace {
    function convertReserveAuctionToBuyItNow(uint256 _editionId, uint128 _listingPrice, uint128 _startDate) external;

    function convertReserveAuctionToOffers(uint256 _editionId, uint128 _startDate) external;
}

interface ITokenBuyNowMarketplace {
    event TokenDeListed(uint256 indexed _tokenId);

    function delistToken(uint256 _tokenId) external;
}

interface ITokenOffersMarketplace {
    event TokenBidPlaced(uint256 indexed _tokenId, address _currentOwner, address _bidder, uint256 _amount);
    event TokenBidAccepted(uint256 indexed _tokenId, address _currentOwner, address _bidder, uint256 _amount);
    event TokenBidRejected(uint256 indexed _tokenId, address _currentOwner, address _bidder, uint256 _amount);
    event TokenBidWithdrawn(uint256 indexed _tokenId, address _bidder);

    function acceptTokenBid(uint256 _tokenId, uint256 _offerPrice) external;

    function rejectTokenBid(uint256 _tokenId) external;

    function withdrawTokenBid(uint256 _tokenId) external;

    function placeTokenBid(uint256 _tokenId) external payable;
    function placeTokenBidFor(uint256 _tokenId, address _bidder) external payable;
}

interface IBuyNowSecondaryMarketplace {
    function listTokenForBuyNow(uint256 _tokenId, uint128 _listingPrice, uint128 _startDate) external;
}

interface IEditionOffersSecondaryMarketplace {
    event EditionBidPlaced(uint256 indexed _editionId, address indexed _bidder, uint256 _bid);
    event EditionBidWithdrawn(uint256 indexed _editionId, address _bidder);
    event EditionBidAccepted(uint256 indexed _tokenId, address _currentOwner, address _bidder, uint256 _amount);

    function placeEditionBid(uint256 _editionId) external payable;
    function placeEditionBidFor(uint256 _editionId, address _bidder) external payable;

    function withdrawEditionBid(uint256 _editionId) external;

    function acceptEditionBid(uint256 _tokenId, uint256 _offerPrice) external;
}

interface IKODAV3SecondarySaleMarketplace is ITokenBuyNowMarketplace, ITokenOffersMarketplace, IEditionOffersSecondaryMarketplace, IBuyNowSecondaryMarketplace {
    function convertReserveAuctionToBuyItNow(uint256 _tokenId, uint128 _listingPrice, uint128 _startDate) external;

    function convertReserveAuctionToOffers(uint256 _tokenId) external;
}

interface IKODAV3GatedMarketplace {

    function createSale(uint256 _editionId) external;

    function createPhase(
        uint256 _editionId,
        uint128 _startTime,
        uint128 _endTime,
        uint128 _priceInWei,
        uint16 _mintCap,
        uint16 _walletMintLimit,
        bytes32 _merkleRoot,
        string calldata _merkleIPFSHash
    ) external;

    function createSaleWithPhases(
        uint256 _editionId,
        uint128[] memory _startTimes,
        uint128[] memory _endTimes,
        uint128[] memory _pricesInWei,
        uint16[] memory _mintCaps,
        uint16[] memory _walletMintLimits,
        bytes32[] memory _merkleRoots,
        string[] memory _merkleIPFSHashes
    ) external;

    function createPhases(
        uint256 _editionId,
        uint128[] memory _startTimes,
        uint128[] memory _endTimes,
        uint128[] memory _pricesInWei,
        uint16[] memory _mintCaps,
        uint16[] memory _walletMintLimits,
        bytes32[] memory _merkleRoots,
        string[] memory _merkleIPFSHashes
    ) external;

    function removePhase(uint256 _editionId, uint256 _phaseId) external;
}
