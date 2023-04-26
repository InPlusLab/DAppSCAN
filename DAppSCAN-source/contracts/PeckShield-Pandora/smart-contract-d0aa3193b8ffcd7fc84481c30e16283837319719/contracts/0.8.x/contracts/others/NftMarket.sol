// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract NftMarket is Ownable, Pausable, ReentrancyGuard {

    using SafeERC20 for IERC20;

    uint256 constant public ONE_HUNDRED_PERCENT = 10000; // 100%

    uint256 constant public MIN_PRICE = 1000000000;

    event SystemFeePercentUpdated(uint256 percent);
    event AdminWalletUpdated(address wallet);
    event Erc20WhitelistUpdated(address[] erc20s, bool status);
    event Erc721WhitelistUpdated(address[] erc721s, bool status);

    event AskCreated(address erc721, address erc20, address seller, uint256 price, uint256 tokenId, uint256 askId);
    event AskCanceled(address erc721, address erc20, address seller, uint256 price, uint256 tokenId, uint256 askId);
    event BidCreated(address erc721, address erc20, address bidder, uint256 price, uint256 tokenId, uint256 bidId, uint256 askId);
    event BidAccepted(address erc721, address erc20, address bidder, address seller, uint256 price, uint256 tokenId, uint256 bidId, uint256 askId);
    event BidCanceled(address erc721, address erc20, address bidder, uint256 price, uint256 tokenId, uint256 bidId, uint256 askId);
    event Payout(address erc721, address erc20, uint256 tokenId, uint256 systemFeePayment, uint256 sellerPayment);
    event TokenSold(address erc721, address erc20, address buyer, address seller, uint256 price, uint256 tokenId, uint256 askId);

    uint256 public systemFeePercent;

    address public adminWallet;

    struct Bid {
        address erc20;
        address bidder;
        uint256 price;
    }

    struct Ask {
        address erc20;
        address seller;
        uint256 price;
    }

    uint256 public totalAsks;
    uint256 public totalBids;

    // erc721 address => token id => ask id => bid id => bid order
    mapping(address => mapping(uint256 => mapping(uint256 => mapping(uint256 => Bid)))) public bids;

    // erc721 address => token id => ask id => sell order
    mapping(address => mapping(uint256 => mapping(uint256 => Ask))) public asks;

    // erc721 address => token id => ask id
    mapping(address => mapping(uint256 => uint256)) public currentAsks;

    // erc20 address => status
    mapping(address => bool) public erc20Whitelist;

    // erc721 address => status
    mapping(address => bool) public erc721Whitelist;

    modifier inWhitelist(address erc721, address erc20) {
        require(erc721Whitelist[erc721] && erc20Whitelist[erc20], "NftMarket: erc721 and erc20 must be in whitelist");
        _;
    }

    constructor(address[] memory erc721s, address[] memory erc20s, address _adminWallet) {
        adminWallet = _adminWallet;

        systemFeePercent = 500; // 5%

        for (uint i = 0; i < erc721s.length; i++) {
            erc721Whitelist[erc721s[i]] = true;
        }

        for (uint i = 0; i < erc20s.length; i++) {
            erc20Whitelist[erc20s[i]] = true;
        }
    }

    function setSystemFeePercent(uint256 percent)
        public
        onlyOwner
    {
        require(percent <= ONE_HUNDRED_PERCENT, "NftMarket: percent is invalid");

        systemFeePercent = percent;

        emit SystemFeePercentUpdated(percent);
    }

    function setAdminWallet(address wallet)
        public
        onlyOwner
    {
        require(wallet != address(0), "NftMarket: address is invalid");

        adminWallet = wallet;

        emit AdminWalletUpdated(wallet);
    }

    function updateErc20Whitelist(address[] memory erc20s, bool status)
        public
        onlyOwner
    {
        uint256 length = erc20s.length;

        require(length > 0, "NftMarket: erc20 list is required");

        for (uint i = 0; i < length; i++) {
            erc20Whitelist[erc20s[i]] = status;
        }

        emit Erc20WhitelistUpdated(erc20s, status);
    }

    function updateErc721Whitelist(address[] memory erc721s, bool status)
        public
        onlyOwner
    {
        uint256 length = erc721s.length;

        require(length > 0, "NftMarket: erc721 list is required");

        for (uint i = 0; i < length; i++) {
            erc721Whitelist[erc721s[i]] = status;
        }

        emit Erc721WhitelistUpdated(erc721s, status);
    }

    function pause()
        public
        onlyOwner
    {
        _pause();
    }

    function unpause()
        public
        onlyOwner
    {
        _unpause();
    }

    function setSalePrice(address erc721, address erc20, uint256 tokenId, uint256 price)
        public
        whenNotPaused
        nonReentrant
        inWhitelist(erc721, erc20)
        returns (uint256) 
    {
        address msgSender = _msgSender();

        require(price >= MIN_PRICE, "NftMarket: price is invalid");

        uint256 oldAsk = currentAsks[erc721][tokenId];

        if (oldAsk == 0) {
            IERC721(erc721).transferFrom(msgSender, address(this), tokenId);

        } else {
            Ask memory info = asks[erc721][tokenId][oldAsk];

            require(info.seller == msgSender, "NftMarket: can not change sale price if sender has not made one");

            emit AskCanceled(erc721, info.erc20, msgSender, info.price, tokenId, oldAsk);

            delete asks[erc721][tokenId][oldAsk];
        }

        totalAsks++;

        uint256 askId = totalAsks;

        asks[erc721][tokenId][askId] = Ask(erc20, msgSender, price);

        currentAsks[erc721][tokenId] = askId;

        emit AskCreated(erc721, erc20, msgSender, price, tokenId, askId);

        return askId;
    }

    function cancelSalePrice(address erc721, uint256 tokenId)
        public
        nonReentrant
    {
        address msgSender = _msgSender();

        uint256 askId = currentAsks[erc721][tokenId];

        Ask memory info = asks[erc721][tokenId][askId];

        require(info.seller == msgSender, "NftMarket: can not cancel sale if sender has not made one");

        IERC721(erc721).transferFrom(address(this), msgSender, tokenId);

        emit AskCanceled(erc721, info.erc20, msgSender, info.price, tokenId, askId);

        delete asks[erc721][tokenId][askId];
        delete currentAsks[erc721][tokenId];
    }

    function bid(address erc721, address erc20, uint256 tokenId, uint256 price, uint256 oldBid)
        public
        whenNotPaused
        nonReentrant
        inWhitelist(erc721, erc20)
        returns (uint256)
    {
        require(price >= MIN_PRICE, "NftMarket: price is invalid");

        uint256 askId = currentAsks[erc721][tokenId];

        require(askId > 0, "NftMarket: no sale");

        totalBids++;

        address msgSender = _msgSender();

        uint256 bidId = totalBids;

        bids[erc721][tokenId][askId][bidId] = Bid(erc20, msgSender, price);

        emit BidCreated(erc721, erc20, msgSender, price, tokenId, bidId, askId);

        if (oldBid > 0) {
            _cancelBid(erc721, tokenId, msgSender, askId, oldBid);
        }

        return bidId;
    }

    function cancelBid(address erc721, uint256 tokenId, uint256 bidId)
        public
        nonReentrant
    {
        uint256 askId = currentAsks[erc721][tokenId];

        require(askId > 0, "NftMarket: no sale");

        _cancelBid(erc721, tokenId, _msgSender(), askId, bidId);
    }

    function _cancelBid(address erc721, uint256 tokenId, address bidder, uint256 askId, uint256 bidId)
        internal
    {
        Bid memory info = bids[erc721][tokenId][askId][bidId];

        require(info.bidder == bidder, "NftMarket: can not cancel a bid if sender has not made one");

        emit BidCanceled(erc721, info.erc20, bidder, info.price, tokenId, bidId, askId);

        delete bids[erc721][tokenId][askId][bidId];
    }

    function acceptBid(address erc721, uint256 tokenId, uint256 bidId)
        public
        whenNotPaused
        nonReentrant
    {
        address msgSender = _msgSender();

        uint256 askId = currentAsks[erc721][tokenId];

        Bid memory info = bids[erc721][tokenId][askId][bidId];

        require(info.bidder != address(0), "NftMarket: can not accept a bid when there is none");

        require(asks[erc721][tokenId][askId].seller == msgSender, "NftMarket: sender is not token owner");

        _payout(erc721, info.erc20, tokenId, info.price, info.bidder, msgSender);

        IERC721(erc721).transferFrom(address(this), info.bidder, tokenId);

        emit BidAccepted(erc721, info.erc20, info.bidder, msgSender, info.price, tokenId, bidId, askId);

        delete asks[erc721][tokenId][askId];
        delete bids[erc721][tokenId][askId][bidId];
        delete currentAsks[erc721][tokenId];
    }

    function buy(address erc721, uint256 tokenId)
        public
        whenNotPaused
        nonReentrant
    {
        address msgSender = _msgSender();

        uint256 askId = currentAsks[erc721][tokenId];

        Ask memory info = asks[erc721][tokenId][askId];

        require(info.price > 0, "NftMarket: token price at 0 are not for sale");

        _payout(erc721, info.erc20, tokenId, info.price, msgSender, info.seller);

        IERC721(erc721).transferFrom(address(this), msgSender, tokenId);

        emit TokenSold(erc721, info.erc20, msgSender, info.seller, info.price, tokenId, askId);

        delete asks[erc721][tokenId][askId];
        delete currentAsks[erc721][tokenId];
    }

    function _payout(address erc721, address erc20, uint256 tokenId, uint256 price, address buyer, address seller)
        internal
    {
        uint systemFeePayment = _calculateSystemFee(price, systemFeePercent);

        if (systemFeePayment > 0) {
            IERC20(erc20).safeTransferFrom(buyer, adminWallet, systemFeePayment);
        }

        uint256 sellerPayment = price - systemFeePayment;

        if (sellerPayment > 0) {
            IERC20(erc20).safeTransferFrom(buyer, seller, sellerPayment);
        }

        emit Payout(erc721, erc20, tokenId, systemFeePayment, sellerPayment);
    }

    function _calculateSystemFee(uint256 price, uint256 feePercent)
        internal
        pure
        returns (uint256)
    {
        return price * feePercent / ONE_HUNDRED_PERCENT;
    }

}