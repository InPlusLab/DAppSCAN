// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {IKOAccessControlsLookup} from "../access/IKOAccessControlsLookup.sol";
import {IKODAV3} from "../core/IKODAV3.sol";
import {IKODAV3PrimarySaleMarketplace} from "./IKODAV3Marketplace.sol";

import {BuyNowMarketplace} from "./BuyNowMarketplace.sol";
import {ReserveAuctionMarketplace} from "./ReserveAuctionMarketplace.sol";
import {BaseMarketplace} from "./BaseMarketplace.sol";

/// @title KnownOrigin Primary Marketplace for all V3 tokens
/// @notice The following listing types are supported: Buy now, Stepped, Reserve and Offers
/// @dev The contract is pausable and has reentrancy guards
/// @author KnownOrigin Labs
contract KODAV3PrimaryMarketplace is
IKODAV3PrimarySaleMarketplace,
BaseMarketplace,
ReserveAuctionMarketplace,
BuyNowMarketplace {

    event PrimaryMarketplaceDeployed();
    event AdminSetKoCommissionOverrideForCreator(address indexed _creator, uint256 _koCommission);
    event AdminSetKoCommissionOverrideForEdition(uint256 indexed _editionId, uint256 _koCommission);
    event ConvertFromBuyNowToOffers(uint256 indexed _editionId, uint128 _startDate);
    event ConvertSteppedAuctionToBuyNow(uint256 indexed _editionId, uint128 _listingPrice, uint128 _startDate);
    event ReserveAuctionConvertedToOffers(uint256 indexed _editionId, uint128 _startDate);

    // KO Commission override definition for a given creator
    struct KOCommissionOverride {
        bool active;
        uint256 koCommission;
    }

    // Offer / Bid definition placed on an edition
    struct Offer {
        uint256 offer;
        address bidder;
        uint256 lockupUntil;
    }

    // Stepped auction definition
    struct Stepped {
        uint128 basePrice;
        uint128 stepPrice;
        uint128 startDate;
        address seller;
        uint16 currentStep;
    }

    /// @notice Edition ID -> KO commission override set by admin
    mapping(uint256 => KOCommissionOverride) public koCommissionOverrideForEditions;

    /// @notice primary sale creator -> KO commission override set by admin
    mapping(address => KOCommissionOverride) public koCommissionOverrideForCreators;

    /// @notice Edition ID to Offer mapping
    mapping(uint256 => Offer) public editionOffers;

    /// @notice Edition ID to StartDate
    mapping(uint256 => uint256) public editionOffersStartDate;

    /// @notice Edition ID to stepped auction
    mapping(uint256 => Stepped) public editionStep;

    /// @notice KO commission on every sale
    uint256 public platformPrimarySaleCommission = 15_00000;  // 15.00000%

    constructor(IKOAccessControlsLookup _accessControls, IKODAV3 _koda, address _platformAccount)
    BaseMarketplace(_accessControls, _koda, _platformAccount) {
        emit PrimaryMarketplaceDeployed();
    }

    // convert from a "buy now" listing and converting to "accepting offers" with an optional start date
    function convertFromBuyNowToOffers(uint256 _editionId, uint128 _startDate)
    public
    whenNotPaused {
        require(
            editionOrTokenListings[_editionId].seller == _msgSender()
            || accessControls.isVerifiedArtistProxy(editionOrTokenListings[_editionId].seller, _msgSender()),
            "Only seller can convert"
        );

        // clear listing
        delete editionOrTokenListings[_editionId];

        // set the start date for the offer (optional)
        editionOffersStartDate[_editionId] = _startDate;

        // Emit event
        emit ConvertFromBuyNowToOffers(_editionId, _startDate);
    }

    // Primary "offers" sale flow

    function enableEditionOffers(uint256 _editionId, uint128 _startDate)
    external
    override
    whenNotPaused
    onlyContract {
        // Set the start date if one supplied
        editionOffersStartDate[_editionId] = _startDate;

        // Emit event
        emit EditionAcceptingOffer(_editionId, _startDate);
    }

    function placeEditionBid(uint256 _editionId)
    public
    override
    payable
    whenNotPaused
    nonReentrant {
        _placeEditionBid(_editionId, _msgSender());
    }

    function placeEditionBidFor(uint256 _editionId, address _bidder)
    public
    override
    payable
    whenNotPaused
    nonReentrant {
        _placeEditionBid(_editionId, _bidder);
    }

    function withdrawEditionBid(uint256 _editionId)
    public
    override
    whenNotPaused
    nonReentrant {
        Offer storage offer = editionOffers[_editionId];
        require(offer.offer > 0, "No open bid");
        require(offer.bidder == _msgSender(), "Not the top bidder");
        require(block.timestamp >= offer.lockupUntil, "Bid lockup not elapsed");

        // send money back to top bidder
        _refundBidder(_editionId, offer.bidder, offer.offer, address(0), 0);

        // emit event
        emit EditionBidWithdrawn(_editionId, _msgSender());

        // delete offer
        delete editionOffers[_editionId];
    }

    function rejectEditionBid(uint256 _editionId)
    public
    override
    whenNotPaused
    nonReentrant {
        Offer storage offer = editionOffers[_editionId];
        require(offer.bidder != address(0), "No open bid");

        address creatorOfEdition = koda.getCreatorOfEdition(_editionId);
        require(
            creatorOfEdition == _msgSender()
            || accessControls.isVerifiedArtistProxy(creatorOfEdition, _msgSender()),
            "Caller not the creator"
        );

        // send money back to top bidder
        _refundBidder(_editionId, offer.bidder, offer.offer, address(0), 0);

        // emit event
        emit EditionBidRejected(_editionId, offer.bidder, offer.offer);

        // delete offer
        delete editionOffers[_editionId];
    }

    function acceptEditionBid(uint256 _editionId, uint256 _offerPrice)
    public
    override
    whenNotPaused
    nonReentrant {
        Offer storage offer = editionOffers[_editionId];
        require(offer.bidder != address(0), "No open bid");
        require(offer.offer >= _offerPrice, "Offer price has changed");

        address creatorOfEdition = koda.getCreatorOfEdition(_editionId);
        require(
            creatorOfEdition == _msgSender()
            || accessControls.isVerifiedArtistProxy(creatorOfEdition, _msgSender()),
            "Not creator"
        );

        // get a new token from the edition to transfer ownership
        uint256 tokenId = _facilitateNextPrimarySale(_editionId, offer.offer, offer.bidder, false);

        // emit event
        emit EditionBidAccepted(_editionId, tokenId, offer.bidder, offer.offer);

        // clear open offer
        delete editionOffers[_editionId];
    }

    // emergency admin "reject" button for stuck bids
    function adminRejectEditionBid(uint256 _editionId) public onlyAdmin nonReentrant {
        Offer storage offer = editionOffers[_editionId];
        require(offer.bidder != address(0), "No open bid");

        // send money back to top bidder
        if (offer.offer > 0) {
            _refundBidder(_editionId, offer.bidder, offer.offer, address(0), 0);
        }

        emit EditionBidRejected(_editionId, offer.bidder, offer.offer);

        // delete offer
        delete editionOffers[_editionId];
    }

    function convertOffersToBuyItNow(uint256 _editionId, uint128 _listingPrice, uint128 _startDate)
    public
    override
    whenNotPaused
    nonReentrant {
        require(!_isEditionListed(_editionId), "Edition is listed");

        address creatorOfEdition = koda.getCreatorOfEdition(_editionId);
        require(
            creatorOfEdition == _msgSender()
            || accessControls.isVerifiedArtistProxy(creatorOfEdition, _msgSender()),
            "Not creator"
        );

        require(_listingPrice >= minBidAmount, "Listing price not enough");

        // send money back to top bidder if existing offer found
        Offer storage offer = editionOffers[_editionId];
        if (offer.offer > 0) {
            _refundBidder(_editionId, offer.bidder, offer.offer, address(0), 0);
        }

        // delete offer
        delete editionOffers[_editionId];

        // delete rest of offer information
        delete editionOffersStartDate[_editionId];

        // Store listing data
        editionOrTokenListings[_editionId] = Listing(_listingPrice, _startDate, _msgSender());

        emit EditionConvertedFromOffersToBuyItNow(_editionId, _listingPrice, _startDate);
    }

    // Primary sale "stepped pricing" flow
    function listSteppedEditionAuction(address _creator, uint256 _editionId, uint128 _basePrice, uint128 _stepPrice, uint128 _startDate)
    public
    override
    whenNotPaused
    onlyContract {
        require(_basePrice >= minBidAmount, "Base price not enough");

        // Store listing data
        editionStep[_editionId] = Stepped(
            _basePrice,
            _stepPrice,
            _startDate,
            _creator,
            uint16(0)
        );

        emit EditionSteppedSaleListed(_editionId, _basePrice, _stepPrice, _startDate);
    }

    function updateSteppedAuction(uint256 _editionId, uint128 _basePrice, uint128 _stepPrice)
    public
    override
    whenNotPaused {
        Stepped storage steppedAuction = editionStep[_editionId];

        require(
            steppedAuction.seller == _msgSender()
            || accessControls.isVerifiedArtistProxy(steppedAuction.seller, _msgSender()),
            "Only seller"
        );

        require(steppedAuction.currentStep == 0, "Only when no sales");
        require(_basePrice >= minBidAmount, "Base price not enough");

        steppedAuction.basePrice = _basePrice;
        steppedAuction.stepPrice = _stepPrice;

        emit EditionSteppedAuctionUpdated(_editionId, _basePrice, _stepPrice);
    }

    function buyNextStep(uint256 _editionId)
    public
    override
    payable
    whenNotPaused
    nonReentrant {
        _buyNextStep(_editionId, _msgSender());
    }

    function buyNextStepFor(uint256 _editionId, address _buyer)
    public
    override
    payable
    whenNotPaused
    nonReentrant {
        _buyNextStep(_editionId, _buyer);
    }

    function _buyNextStep(uint256 _editionId, address _buyer) internal {
        Stepped storage steppedAuction = editionStep[_editionId];
        require(steppedAuction.seller != address(0), "Edition not listed for stepped auction");
        require(steppedAuction.startDate <= block.timestamp, "Not started yet");

        uint256 expectedPrice = _getNextEditionSteppedPrice(_editionId);
        require(msg.value >= expectedPrice, "Expected price not met");

        uint256 tokenId = _facilitateNextPrimarySale(_editionId, expectedPrice, _buyer, true);

        // Bump the current step
        uint16 step = steppedAuction.currentStep;

        // no safemath for uint16
        steppedAuction.currentStep = step + 1;

        // send back excess if supplied - will allow UX flow of setting max price to pay
        if (msg.value > expectedPrice) {
            (bool success,) = _msgSender().call{value : msg.value - expectedPrice}("");
            require(success, "failed to send overspend back");
        }

        emit EditionSteppedSaleBuy(_editionId, tokenId, _buyer, expectedPrice, step);
    }

    // creates an exit from a step if required but forces a buy now price
    function convertSteppedAuctionToListing(uint256 _editionId, uint128 _listingPrice, uint128 _startDate)
    public
    override
    nonReentrant
    whenNotPaused {
        Stepped storage steppedAuction = editionStep[_editionId];
        require(_listingPrice >= minBidAmount, "List price not enough");

        require(
            steppedAuction.seller == _msgSender()
            || accessControls.isVerifiedArtistProxy(steppedAuction.seller, _msgSender()),
            "Only seller can convert"
        );

        // Store listing data
        editionOrTokenListings[_editionId] = Listing(_listingPrice, _startDate, steppedAuction.seller);

        // emit event
        emit ConvertSteppedAuctionToBuyNow(_editionId, _listingPrice, _startDate);

        // Clear up the step logic
        delete editionStep[_editionId];
    }

    function convertSteppedAuctionToOffers(uint256 _editionId, uint128 _startDate)
    public
    override
    whenNotPaused {
        Stepped storage steppedAuction = editionStep[_editionId];

        require(
            steppedAuction.seller == _msgSender()
            || accessControls.isVerifiedArtistProxy(steppedAuction.seller, _msgSender()),
            "Only seller can convert"
        );

        // set the start date for the offer (optional)
        editionOffersStartDate[_editionId] = _startDate;

        // Clear up the step logic
        delete editionStep[_editionId];

        emit ConvertFromBuyNowToOffers(_editionId, _startDate);
    }

    // Get the next
    function getNextEditionSteppedPrice(uint256 _editionId) public view returns (uint256 price) {
        price = _getNextEditionSteppedPrice(_editionId);
    }

    function _getNextEditionSteppedPrice(uint256 _editionId) internal view returns (uint256 price) {
        Stepped storage steppedAuction = editionStep[_editionId];
        uint256 stepAmount = uint256(steppedAuction.stepPrice) * uint256(steppedAuction.currentStep);
        price = uint256(steppedAuction.basePrice) + stepAmount;
    }

    function convertReserveAuctionToBuyItNow(uint256 _editionId, uint128 _listingPrice, uint128 _startDate)
    public
    override
    whenNotPaused
    nonReentrant {
        require(_listingPrice >= minBidAmount, "Listing price not enough");
        _removeReserveAuctionListing(_editionId);

        editionOrTokenListings[_editionId] = Listing(_listingPrice, _startDate, _msgSender());

        emit ReserveAuctionConvertedToBuyItNow(_editionId, _listingPrice, _startDate);
    }

    function convertReserveAuctionToOffers(uint256 _editionId, uint128 _startDate)
    public
    override
    whenNotPaused
    nonReentrant {
        _removeReserveAuctionListing(_editionId);

        // set the start date for the offer (optional)
        editionOffersStartDate[_editionId] = _startDate;

        emit ReserveAuctionConvertedToOffers(_editionId, _startDate);
    }

    // admin

    function updatePlatformPrimarySaleCommission(uint256 _platformPrimarySaleCommission) public onlyAdmin {
        platformPrimarySaleCommission = _platformPrimarySaleCommission;
        emit AdminUpdatePlatformPrimarySaleCommission(_platformPrimarySaleCommission);
    }

    function setKoCommissionOverrideForCreator(address _creator, bool _active, uint256 _koCommission) public onlyAdmin {
        KOCommissionOverride storage koCommissionOverride = koCommissionOverrideForCreators[_creator];
        koCommissionOverride.active = _active;
        koCommissionOverride.koCommission = _koCommission;

        emit AdminSetKoCommissionOverrideForCreator(_creator, _koCommission);
    }

    function setKoCommissionOverrideForEdition(uint256 _editionId, bool _active, uint256 _koCommission) public onlyAdmin {
        KOCommissionOverride storage koCommissionOverride = koCommissionOverrideForEditions[_editionId];
        koCommissionOverride.active = _active;
        koCommissionOverride.koCommission = _koCommission;

        emit AdminSetKoCommissionOverrideForEdition(_editionId, _koCommission);
    }

    // internal

    function _isListingPermitted(uint256 _editionId) internal view override returns (bool) {
        return !_isEditionListed(_editionId);
    }

    function _isReserveListingPermitted(uint256 _editionId) internal view override returns (bool) {
        return koda.getSizeOfEdition(_editionId) == 1 && accessControls.hasContractRole(_msgSender());
    }

    function _hasReserveListingBeenInvalidated(uint256 _id) internal view override returns (bool) {
        bool isApprovalActiveForMarketplace = koda.isApprovedForAll(
            editionOrTokenWithReserveAuctions[_id].seller,
            address(this)
        );

        return !isApprovalActiveForMarketplace || koda.isSalesDisabledOrSoldOut(_id);
    }

    function _isBuyNowListingPermitted(uint256) internal view override returns (bool) {
        return accessControls.hasContractRole(_msgSender());
    }

    function _processSale(uint256 _id, uint256 _paymentAmount, address _buyer, address) internal override returns (uint256) {
        return _facilitateNextPrimarySale(_id, _paymentAmount, _buyer, false);
    }

    function _facilitateNextPrimarySale(uint256 _editionId, uint256 _paymentAmount, address _buyer, bool _reverse) internal returns (uint256) {
        // for stepped sales, should they be sold in reverse order ie. 10...1 and not 1...10?
        // get next token to sell along with the royalties recipient and the original creator
        (address receiver, address creator, uint256 tokenId) = _reverse
        ? koda.facilitateReversePrimarySale(_editionId)
        : koda.facilitateNextPrimarySale(_editionId);

        // split money
        _handleEditionSaleFunds(_editionId, creator, receiver, _paymentAmount);

        // send token to buyer (assumes approval has been made, if not then this will fail)
        koda.safeTransferFrom(creator, _buyer, tokenId);

        // N:B. open offers are left once sold out for the bidder to withdraw or the artist to reject

        return tokenId;
    }

    function _handleEditionSaleFunds(uint256 _editionId, address _creator, address _receiver, uint256 _paymentAmount) internal {
        uint256 primarySaleCommission;

        if (koCommissionOverrideForEditions[_editionId].active) {
            primarySaleCommission = koCommissionOverrideForEditions[_editionId].koCommission;
        }
        else if (koCommissionOverrideForCreators[_creator].active) {
            primarySaleCommission = koCommissionOverrideForCreators[_creator].koCommission;
        }
        else {
            primarySaleCommission = platformPrimarySaleCommission;
        }

        uint256 koCommission = (_paymentAmount / modulo) * primarySaleCommission;
        if (koCommission > 0) {
            (bool koCommissionSuccess,) = platformAccount.call{value : koCommission}("");
            require(koCommissionSuccess, "Edition commission payment failed");
        }

        (bool success,) = _receiver.call{value : _paymentAmount - koCommission}("");
        require(success, "Edition payment failed");
    }

    // as offers are always possible, we wont count it as a listing
    function _isEditionListed(uint256 _editionId) internal view returns (bool) {
        if (editionOrTokenListings[_editionId].seller != address(0)) {
            return true;
        }

        if (editionStep[_editionId].seller != address(0)) {
            return true;
        }

        if (editionOrTokenWithReserveAuctions[_editionId].seller != address(0)) {
            return true;
        }

        return false;
    }

    function _placeEditionBid(uint256 _editionId, address _bidder) internal {
        require(!_isEditionListed(_editionId), "Edition is listed");

        Offer storage offer = editionOffers[_editionId];
        require(msg.value >= offer.offer + minBidAmount, "Bid not high enough");

        // Honor start date if set
        uint256 startDate = editionOffersStartDate[_editionId];
        if (startDate > 0) {
            require(block.timestamp >= startDate, "Not yet accepting offers");

            // elapsed, so free storage
            delete editionOffersStartDate[_editionId];
        }

        // send money back to top bidder if existing offer found
        if (offer.offer > 0) {
            _refundBidder(_editionId, offer.bidder, offer.offer, _msgSender(), msg.value);
        }

        // setup offer
        editionOffers[_editionId] = Offer(msg.value, _bidder, _getLockupTime());

        emit EditionBidPlaced(_editionId, _bidder, msg.value);
    }
}

