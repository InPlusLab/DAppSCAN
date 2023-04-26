// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {IKOAccessControlsLookup} from "../access/IKOAccessControlsLookup.sol";
import {IKODAV3} from "../core/IKODAV3.sol";

import {BaseMarketplace} from "./BaseMarketplace.sol";
import {IReserveAuctionMarketplace} from "./IKODAV3Marketplace.sol";

abstract contract ReserveAuctionMarketplace is IReserveAuctionMarketplace, BaseMarketplace {
    event AdminUpdateReserveAuctionBidExtensionWindow(uint128 _reserveAuctionBidExtensionWindow);
    event AdminUpdateReserveAuctionLengthOnceReserveMet(uint128 _reserveAuctionLengthOnceReserveMet);

    // Reserve auction definition
    struct ReserveAuction {
        address seller;
        address bidder;
        uint128 reservePrice;
        uint128 bid;
        uint128 startDate;
        uint128 biddingEnd;
    }

    /// @notice 1 of 1 edition ID to reserve auction definition
    mapping(uint256 => ReserveAuction) public editionOrTokenWithReserveAuctions;

    /// @notice A reserve auction will be extended by this amount of time if a bid is received near the end
    uint128 public reserveAuctionBidExtensionWindow = 15 minutes;

    /// @notice Length that bidding window remains open once the reserve price for an auction has been met
    uint128 public reserveAuctionLengthOnceReserveMet = 24 hours;

    function listForReserveAuction(
        address _creator,
        uint256 _id,
        uint128 _reservePrice,
        uint128 _startDate
    ) public
    override
    whenNotPaused {
        require(_isListingPermitted(_id), "Listing not permitted");
        require(_isReserveListingPermitted(_id), "Reserve listing not permitted");
        require(_reservePrice >= minBidAmount, "Reserve price must be at least min bid");

        editionOrTokenWithReserveAuctions[_id] = ReserveAuction({
        seller : _creator,
        bidder : address(0),
        reservePrice : _reservePrice,
        startDate : _startDate,
        biddingEnd : 0,
        bid : 0
        });

        emit ListedForReserveAuction(_id, _reservePrice, _startDate);
    }

    function placeBidOnReserveAuction(uint256 _id)
    public
    override
    payable
    whenNotPaused
    nonReentrant {
        _placeBidOnReserveAuction(_id, _msgSender());
    }

    function placeBidOnReserveAuctionFor(uint256 _id, address _bidder)
    public
    override
    payable
    whenNotPaused
    nonReentrant {
        _placeBidOnReserveAuction(_id, _bidder);
    }

    function _placeBidOnReserveAuction(uint256 _id, address _bidder) internal {
        ReserveAuction storage reserveAuction = editionOrTokenWithReserveAuctions[_id];
        require(reserveAuction.reservePrice > 0, "Not set up for reserve auction");
        require(block.timestamp >= reserveAuction.startDate, "Not accepting bids yet");
        require(msg.value >= reserveAuction.bid + minBidAmount, "You have not exceeded previous bid by min bid amount");

        uint128 originalBiddingEnd = reserveAuction.biddingEnd;

        // If the reserve has been met, then bidding will end in 24 hours
        // if we are near the end, we have bids, then extend the bidding end
        bool isCountDownTriggered = originalBiddingEnd > 0;

        if (msg.value >= reserveAuction.reservePrice && !isCountDownTriggered) {
            reserveAuction.biddingEnd = uint128(block.timestamp) + reserveAuctionLengthOnceReserveMet;
        }
        else if (isCountDownTriggered) {

            // if a bid has been placed, then we will have a bidding end timestamp
            // and we need to ensure no one can bid beyond this
            require(block.timestamp < originalBiddingEnd, "No longer accepting bids");
            uint128 secondsUntilBiddingEnd = originalBiddingEnd - uint128(block.timestamp);

            // If bid received with in the extension window, extend bidding end
            if (secondsUntilBiddingEnd <= reserveAuctionBidExtensionWindow) {
                reserveAuction.biddingEnd = reserveAuction.biddingEnd + reserveAuctionBidExtensionWindow;
            }
        }

        // if someone else has previously bid, there is a bid we need to refund
        if (reserveAuction.bid > 0) {
            _refundBidder(_id, reserveAuction.bidder, reserveAuction.bid, _bidder, msg.value);
        }

        reserveAuction.bid = uint128(msg.value);
        reserveAuction.bidder = _bidder;

        emit BidPlacedOnReserveAuction(_id, reserveAuction.seller, _bidder, msg.value, originalBiddingEnd, reserveAuction.biddingEnd);
    }

    function resultReserveAuction(uint256 _id)
    public
    override
    whenNotPaused
    nonReentrant {
        ReserveAuction storage reserveAuction = editionOrTokenWithReserveAuctions[_id];

        require(reserveAuction.reservePrice > 0, "No active auction");
        require(reserveAuction.bid >= reserveAuction.reservePrice, "Reserve not met");
        require(block.timestamp > reserveAuction.biddingEnd, "Bidding has not yet ended");

        // N:B. anyone can result the action as only the winner and seller are compensated

        address winner = reserveAuction.bidder;
        address seller = reserveAuction.seller;
        uint256 winningBid = reserveAuction.bid;
        delete editionOrTokenWithReserveAuctions[_id];

        _processSale(_id, winningBid, winner, seller);

        emit ReserveAuctionResulted(_id, winningBid, seller, winner, _msgSender());
    }

    // Only permit bid withdrawals if reserve not met
    function withdrawBidFromReserveAuction(uint256 _id)
    public
    override
    whenNotPaused
    nonReentrant {
        ReserveAuction storage reserveAuction = editionOrTokenWithReserveAuctions[_id];

        require(reserveAuction.reservePrice > 0, "No reserve auction in flight");
        require(reserveAuction.bid < reserveAuction.reservePrice, "Bids can only be withdrawn if reserve not met");
        require(reserveAuction.bidder == _msgSender(), "Only the bidder can withdraw their bid");

        uint256 bidToRefund = reserveAuction.bid;
        _refundBidder(_id, reserveAuction.bidder, bidToRefund, address(0), 0);

        reserveAuction.bidder = address(0);
        reserveAuction.bid = 0;

        emit BidWithdrawnFromReserveAuction(_id, _msgSender(), uint128(bidToRefund));
    }

    // can only do this if the reserve has not been met
    function updateReservePriceForReserveAuction(uint256 _id, uint128 _reservePrice)
    public
    override
    whenNotPaused
    nonReentrant {
        ReserveAuction storage reserveAuction = editionOrTokenWithReserveAuctions[_id];

        require(
            reserveAuction.seller == _msgSender()
            || accessControls.isVerifiedArtistProxy(reserveAuction.seller, _msgSender()),
            "Not the seller"
        );

        require(reserveAuction.biddingEnd == 0, "Reserve countdown commenced");
        require(_reservePrice >= minBidAmount, "Reserve must be at least min bid");

        // Trigger countdown if new reserve price is greater than any current bids
        if (reserveAuction.bid >= _reservePrice) {
            reserveAuction.biddingEnd = uint128(block.timestamp) + reserveAuctionLengthOnceReserveMet;
        }

        reserveAuction.reservePrice = _reservePrice;

        emit ReservePriceUpdated(_id, _reservePrice);
    }

    function emergencyExitBidFromReserveAuction(uint256 _id)
    public
    override
    whenNotPaused
    nonReentrant {
        ReserveAuction storage reserveAuction = editionOrTokenWithReserveAuctions[_id];

        require(reserveAuction.bid > 0, "No bid in flight");
        require(_hasReserveListingBeenInvalidated(_id), "Bid cannot be withdrawn as reserve auction listing is valid");

        bool isSeller = reserveAuction.seller == _msgSender();
        bool isBidder = reserveAuction.bidder == _msgSender();
        require(
            isSeller
            || isBidder
            || accessControls.isVerifiedArtistProxy(reserveAuction.seller, _msgSender())
            || accessControls.hasContractOrAdminRole(_msgSender()),
            "Only seller, bidder, contract or platform admin"
        );
        // external call done last as a gas optimisation i.e. it wont be called if isSeller || isBidder is true

        _refundBidder(_id, reserveAuction.bidder, reserveAuction.bid, address(0), 0);

        emit EmergencyBidWithdrawFromReserveAuction(_id, reserveAuction.bidder, reserveAuction.bid);

        delete editionOrTokenWithReserveAuctions[_id];
    }

    function updateReserveAuctionBidExtensionWindow(uint128 _reserveAuctionBidExtensionWindow) onlyAdmin public {
        reserveAuctionBidExtensionWindow = _reserveAuctionBidExtensionWindow;
        emit AdminUpdateReserveAuctionBidExtensionWindow(_reserveAuctionBidExtensionWindow);
    }

    function updateReserveAuctionLengthOnceReserveMet(uint128 _reserveAuctionLengthOnceReserveMet) onlyAdmin public {
        reserveAuctionLengthOnceReserveMet = _reserveAuctionLengthOnceReserveMet;
        emit AdminUpdateReserveAuctionLengthOnceReserveMet(_reserveAuctionLengthOnceReserveMet);
    }

    function _isReserveListingPermitted(uint256 _id) internal virtual returns (bool);

    function _hasReserveListingBeenInvalidated(uint256 _id) internal virtual returns (bool);

    function _removeReserveAuctionListing(uint256 _id) internal {
        ReserveAuction storage reserveAuction = editionOrTokenWithReserveAuctions[_id];

        require(reserveAuction.reservePrice > 0, "No active auction");
        require(reserveAuction.bid < reserveAuction.reservePrice, "Can only convert before reserve met");
        require(reserveAuction.seller == _msgSender(), "Only the seller can convert");

        // refund any bids
        if (reserveAuction.bid > 0) {
            _refundBidder(_id, reserveAuction.bidder, reserveAuction.bid, address(0), 0);
        }

        delete editionOrTokenWithReserveAuctions[_id];
    }
}
