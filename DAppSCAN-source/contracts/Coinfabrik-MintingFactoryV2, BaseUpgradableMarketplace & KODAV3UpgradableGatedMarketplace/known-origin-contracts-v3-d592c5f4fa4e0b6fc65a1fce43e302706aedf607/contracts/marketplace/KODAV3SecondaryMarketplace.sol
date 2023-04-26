// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {IKODAV3SecondarySaleMarketplace} from "./IKODAV3Marketplace.sol";
import {IKOAccessControlsLookup} from "../access/IKOAccessControlsLookup.sol";
import {IKODAV3} from "../core/IKODAV3.sol";
import {BuyNowMarketplace} from "./BuyNowMarketplace.sol";
import {ReserveAuctionMarketplace} from "./ReserveAuctionMarketplace.sol";
import {BaseMarketplace} from "./BaseMarketplace.sol";

/// @title KnownOrigin Secondary Marketplace for all V3 tokens
/// @notice The following listing types are supported: Buy now, Reserve and Offers
/// @dev The contract is pausable and has reentrancy guards
/// @author KnownOrigin Labs
contract KODAV3SecondaryMarketplace is
IKODAV3SecondarySaleMarketplace,
BaseMarketplace,
BuyNowMarketplace,
ReserveAuctionMarketplace {

    event SecondaryMarketplaceDeployed();
    event AdminUpdateSecondarySaleCommission(uint256 _platformSecondarySaleCommission);
    event ConvertFromBuyNowToOffers(uint256 indexed _tokenId, uint128 _startDate);
    event ReserveAuctionConvertedToOffers(uint256 indexed _tokenId);

    struct Offer {
        uint256 offer;
        address bidder;
        uint256 lockupUntil;
    }

    // Token ID to Offer mapping
    mapping(uint256 => Offer) public tokenBids;

    // Edition ID to Offer (an offer on any token in an edition)
    mapping(uint256 => Offer) public editionBids;

    uint256 public platformSecondarySaleCommission = 2_50000;  // 2.50000%

    constructor(IKOAccessControlsLookup _accessControls, IKODAV3 _koda, address _platformAccount)
    BaseMarketplace(_accessControls, _koda, _platformAccount) {
        emit SecondaryMarketplaceDeployed();
    }

    function listTokenForBuyNow(uint256 _tokenId, uint128 _listingPrice, uint128 _startDate)
    public
    override
    whenNotPaused {
        listForBuyNow(_msgSender(), _tokenId, _listingPrice, _startDate);
    }

    function delistToken(uint256 _tokenId)
    public
    override
    whenNotPaused {
        // check listing found
        require(editionOrTokenListings[_tokenId].seller != address(0), "No listing found");

        // check owner is caller
        require(koda.ownerOf(_tokenId) == _msgSender(), "Not token owner");

        // remove the listing
        delete editionOrTokenListings[_tokenId];

        emit TokenDeListed(_tokenId);
    }

    // Secondary sale "offer" flow

    function placeEditionBid(uint256 _editionId)
    public
    payable
    override
    whenNotPaused
    nonReentrant {
        _placeEditionBidFor(_editionId, _msgSender());
    }

    function placeEditionBidFor(uint256 _editionId, address _bidder)
    public
    payable
    override
    whenNotPaused
    nonReentrant {
        _placeEditionBidFor(_editionId, _bidder);
    }

    function withdrawEditionBid(uint256 _editionId)
    public
    override
    whenNotPaused
    nonReentrant {
        Offer storage offer = editionBids[_editionId];

        // caller must be bidder
        require(offer.bidder == _msgSender(), "Not bidder");

        // cannot withdraw before lockup period elapses
        require(block.timestamp >= offer.lockupUntil, "Bid lockup not elapsed");

        // send money back to top bidder
        _refundBidder(_editionId, offer.bidder, offer.offer, address(0), 0);

        // delete offer
        delete editionBids[_editionId];

        emit EditionBidWithdrawn(_editionId, _msgSender());
    }

    function acceptEditionBid(uint256 _tokenId, uint256 _offerPrice)
    public
    override
    whenNotPaused
    nonReentrant {
        uint256 editionId = koda.getEditionIdOfToken(_tokenId);

        Offer memory offer = editionBids[editionId];
        require(offer.bidder != address(0), "No open bid");
        require(offer.offer >= _offerPrice, "Offer price has changed");

        address currentOwner = koda.ownerOf(_tokenId);
        require(currentOwner == _msgSender(), "Not current owner");

        require(!_isTokenListed(_tokenId), "The token is listed so cannot accept an edition bid");

        _facilitateSecondarySale(_tokenId, offer.offer, currentOwner, offer.bidder);

        // clear open offer
        delete editionBids[editionId];

        emit EditionBidAccepted(_tokenId, currentOwner, offer.bidder, offer.offer);
    }

    function placeTokenBid(uint256 _tokenId)
    public
    payable
    override
    whenNotPaused
    nonReentrant {
        _placeTokenBidFor(_tokenId, _msgSender());
    }

    function placeTokenBidFor(uint256 _tokenId, address _bidder)
    public
    payable
    override
    whenNotPaused
    nonReentrant {
        _placeTokenBidFor(_tokenId, _bidder);
    }

    function withdrawTokenBid(uint256 _tokenId)
    public
    override
    whenNotPaused
    nonReentrant {
        Offer storage offer = tokenBids[_tokenId];

        // caller must be bidder
        require(offer.bidder == _msgSender(), "Not bidder");

        // cannot withdraw before lockup period elapses
        require(block.timestamp >= offer.lockupUntil, "Bid lockup not elapsed");

        // send money back to top bidder
        _refundBidder(_tokenId, offer.bidder, offer.offer, address(0), 0);

        // delete offer
        delete tokenBids[_tokenId];

        emit TokenBidWithdrawn(_tokenId, _msgSender());
    }

    function rejectTokenBid(uint256 _tokenId)
    public
    override
    whenNotPaused
    nonReentrant {
        Offer memory offer = tokenBids[_tokenId];
        require(offer.bidder != address(0), "No open bid");

        address currentOwner = koda.ownerOf(_tokenId);
        require(currentOwner == _msgSender(), "Not current owner");

        // send money back to top bidder
        _refundBidder(_tokenId, offer.bidder, offer.offer, address(0), 0);

        // delete offer
        delete tokenBids[_tokenId];

        emit TokenBidRejected(_tokenId, currentOwner, offer.bidder, offer.offer);
    }

    function acceptTokenBid(uint256 _tokenId, uint256 _offerPrice)
    public
    override
    whenNotPaused
    nonReentrant {
        Offer memory offer = tokenBids[_tokenId];
        require(offer.bidder != address(0), "No open bid");
        require(offer.offer >= _offerPrice, "Offer price has changed");

        address currentOwner = koda.ownerOf(_tokenId);
        require(currentOwner == _msgSender(), "Not current owner");

        _facilitateSecondarySale(_tokenId, offer.offer, currentOwner, offer.bidder);

        // clear open offer
        delete tokenBids[_tokenId];

        emit TokenBidAccepted(_tokenId, currentOwner, offer.bidder, offer.offer);
    }

    // emergency admin "reject" button for stuck bids
    function adminRejectTokenBid(uint256 _tokenId)
    public
    nonReentrant
    onlyAdmin {
        Offer memory offer = tokenBids[_tokenId];
        require(offer.bidder != address(0), "No open bid");

        // send money back to top bidder
        if (offer.offer > 0) {
            _refundBidder(_tokenId, offer.bidder, offer.offer, address(0), 0);
        }

        // delete offer
        delete tokenBids[_tokenId];

        emit TokenBidRejected(_tokenId, koda.ownerOf(_tokenId), offer.bidder, offer.offer);
    }

    function convertReserveAuctionToBuyItNow(uint256 _tokenId, uint128 _listingPrice, uint128 _startDate)
    public
    override
    whenNotPaused
    nonReentrant {
        require(_listingPrice >= minBidAmount, "Listing price not enough");
        _removeReserveAuctionListing(_tokenId);

        editionOrTokenListings[_tokenId] = Listing(_listingPrice, _startDate, _msgSender());

        emit ReserveAuctionConvertedToBuyItNow(_tokenId, _listingPrice, _startDate);
    }

    function convertReserveAuctionToOffers(uint256 _tokenId)
    public
    override
    whenNotPaused
    nonReentrant {
        _removeReserveAuctionListing(_tokenId);
        emit ReserveAuctionConvertedToOffers(_tokenId);
    }

    //////////////////////////////
    // Secondary sale "helpers" //
    //////////////////////////////

    function _facilitateSecondarySale(uint256 _tokenId, uint256 _paymentAmount, address _seller, address _buyer) internal {
        (address _royaltyRecipient, uint256 _royaltyAmount) = koda.royaltyInfo(_tokenId, _paymentAmount);

        // split money
        handleSecondarySaleFunds(_seller, _royaltyRecipient, _paymentAmount, _royaltyAmount);

        // N:B. open offers are left for the bidder to withdraw or the new token owner to reject/accept

        // send token to buyer
        koda.safeTransferFrom(_seller, _buyer, _tokenId);
    }

    function handleSecondarySaleFunds(
        address _seller,
        address _royaltyRecipient,
        uint256 _paymentAmount,
        uint256 _creatorRoyalties
    ) internal {
        // pay royalties
        (bool creatorSuccess,) = _royaltyRecipient.call{value : _creatorRoyalties}("");
        require(creatorSuccess, "Token payment failed");

        // pay platform fee
        uint256 koCommission = (_paymentAmount / modulo) * platformSecondarySaleCommission;
        (bool koCommissionSuccess,) = platformAccount.call{value : koCommission}("");
        require(koCommissionSuccess, "Token commission payment failed");

        // pay seller
        (bool success,) = _seller.call{value : _paymentAmount - _creatorRoyalties - koCommission}("");
        require(success, "Token payment failed");
    }

    // Admin Methods

    function updatePlatformSecondarySaleCommission(uint256 _platformSecondarySaleCommission) public onlyAdmin {
        platformSecondarySaleCommission = _platformSecondarySaleCommission;
        emit AdminUpdateSecondarySaleCommission(_platformSecondarySaleCommission);
    }

    // internal

    function _isListingPermitted(uint256 _tokenId) internal view override returns (bool) {
        return !_isTokenListed(_tokenId);
    }

    function _isReserveListingPermitted(uint256 _tokenId) internal view override returns (bool) {
        return koda.ownerOf(_tokenId) == _msgSender();
    }

    function _hasReserveListingBeenInvalidated(uint256 _id) internal view override returns (bool) {
        bool isApprovalActiveForMarketplace = koda.isApprovedForAll(
            editionOrTokenWithReserveAuctions[_id].seller,
            address(this)
        );

        return !isApprovalActiveForMarketplace || koda.ownerOf(_id) != editionOrTokenWithReserveAuctions[_id].seller;
    }

    function _isBuyNowListingPermitted(uint256 _tokenId) internal view override returns (bool) {
        return koda.ownerOf(_tokenId) == _msgSender();
    }

    function _processSale(
        uint256 _tokenId,
        uint256 _paymentAmount,
        address _buyer,
        address _seller
    ) internal override returns (uint256) {
        _facilitateSecondarySale(_tokenId, _paymentAmount, _seller, _buyer);
        return _tokenId;
    }

    // as offers are always possible, we wont count it as a listing
    function _isTokenListed(uint256 _tokenId) internal view returns (bool) {
        address currentOwner = koda.ownerOf(_tokenId);

        // listing not set
        if (editionOrTokenListings[_tokenId].seller == currentOwner) {
            return true;
        }

        // listing not set
        if (editionOrTokenWithReserveAuctions[_tokenId].seller == currentOwner) {
            return true;
        }

        return false;
    }

    function _placeEditionBidFor(uint256 _editionId, address _bidder) internal {
        require(koda.editionExists(_editionId), "Edition does not exist");

        // Check for highest offer
        Offer storage offer = editionBids[_editionId];
        require(msg.value >= offer.offer + minBidAmount, "Bid not high enough");

        // send money back to top bidder if existing offer found
        if (offer.offer > 0) {
            _refundBidder(_editionId, offer.bidder, offer.offer, _bidder, msg.value);
        }

        // setup offer
        editionBids[_editionId] = Offer(msg.value, _bidder, _getLockupTime());

        emit EditionBidPlaced(_editionId, _bidder, msg.value);
    }

    function _placeTokenBidFor(uint256 _tokenId, address _bidder) internal {
        require(!_isTokenListed(_tokenId), "Token is listed");

        // Check for highest offer
        Offer storage offer = tokenBids[_tokenId];
        require(msg.value >= offer.offer + minBidAmount, "Bid not high enough");

        // send money back to top bidder if existing offer found
        if (offer.offer > 0) {
            _refundBidder(_tokenId, offer.bidder, offer.offer, _bidder, msg.value);
        }

        // setup offer
        tokenBids[_tokenId] = Offer(msg.value, _bidder, _getLockupTime());

        emit TokenBidPlaced(_tokenId, koda.ownerOf(_tokenId), _bidder, msg.value);
    }
}
