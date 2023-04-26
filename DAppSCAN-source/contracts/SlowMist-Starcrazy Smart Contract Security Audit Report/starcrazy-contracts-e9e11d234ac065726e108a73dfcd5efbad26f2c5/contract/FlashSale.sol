pragma solidity ^0.5.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./aliana/GFAccessControl.sol";
import "./aliana/IAliana.sol";
import "./aliana/AuctionOwner.sol";
import "./math/SafeMath.sol";

/// @title Auction Core
/// @dev Contains models, variables, and internal methods for the auction.
/// @notice We omit a fallback function to prevent accidental sends to this contract.
contract FlashSaleBase is AuctionOwner, GFAccessControl {
    using SafeMath for uint256;
    uint256 maxBiddingNum;
    uint256[] biddingId;
    uint256 public lastBiddingId;
    uint256 c_startingPrice = 1e16; // 0.01 GFT
    uint256 c_duration = 50; // 300s
    uint256 c_minAddPrice = 1e16; // 0.01 GFT
    uint256 c_startBlockOffset; // begin of the block
    uint256 c_cycleBlock; // cycle time
    uint256 c_maxCycle; // max cycle

    // Represents an auction on an NFT
    struct Auction {
        uint256 currentPrice;
        address buyer;
        uint64 endAt;
        bool taked;
    }

    // Reference to contract tracking NFT ownership
    IAliana public alianaContract;

    // Cut owner takes on each auction, measured in basis points (1/100 of a percent).
    // Values 0-10,000 map to 0%-100%
    uint256 public ownerCut;

    // The gae TOKEN
    IERC20 public gaeToken;

    // Map from token ID to their corresponding auction.
    mapping(uint256 => Auction) tokenIdToAuction;

    struct GeneEntry {
        uint256 gene;
        bool used;
    }
    // Map from token ID to their gene value.
    mapping(uint256 => GeneEntry) tokenIdToGene;

    event TakeBid(
        uint256 indexed tokenId,
        address indexed winner,
        uint256 totalPrice
    );

    event Bid(uint256 indexed tokenId, address indexed buyer, uint256 price);

    constructor(IERC20 _gaeToken, uint256 _cycleBlock) public {
        gaeToken = _gaeToken;
        updateMaxBiddingNum(6);
        setStartBlockOffset(block.number);
        setCycleBlock(_cycleBlock);
    }

    function updateMaxBiddingNum(uint256 _value) public onlyCEO {
        maxBiddingNum = _value;
        for (uint256 i = maxBiddingNum; i < biddingId.length; i++) {
            Auction storage auction = tokenIdToAuction[biddingId[i]];
            require(
                !_hasAuctionByInfo(auction) || !_isOnAuction(auction),
                "FlashSale: reduced capacity auction in bidding"
            );
        }
        biddingId.length = maxBiddingNum;
        _updateBidding();
    }

    function getStartingPrice() public view returns (uint256) {
        return c_startingPrice;
    }

    function setStartingPrice(uint256 _value) public onlyCEO {
        c_startingPrice = _value;
    }

    function getCycleBlock() public view returns (uint256) {
        return c_cycleBlock;
    }

    function setCycleBlock(uint256 _cycleBlock) public onlyCEO {
        require(_cycleBlock > 0, "require _cycleBlock > 0");
        require(_cycleBlock > c_duration, "require _cycleBlock > c_duration");
        c_cycleBlock = _cycleBlock;
    }

    function getStartBlockOffset() public view returns (uint256) {
        return c_startBlockOffset;
    }

    function setStartBlockOffset(uint256 _startBlockOffset) public onlyCEO {
        require(
            _startBlockOffset <= block.number,
            "require _startBlockOffset <= block.number"
        );
        c_startBlockOffset = _startBlockOffset;
    }

    function getMaxCycle() public view returns (uint256) {
        return c_maxCycle;
    }

    function setMaxCycle(uint256 _maxCycle) public onlyCEO {
        c_maxCycle = _maxCycle;
    }

    function getDuration() public view returns (uint256) {
        return c_duration;
    }

    function setDuration(uint256 _value) public onlyCEO {
        require(_value > 0, "require _value > 0");
        require(c_cycleBlock > _value, "require c_cycleBlock > _value");
        c_duration = _value;
    }

    function getLatestActivity()
        public
        view
        returns (uint256 begin, uint256 end)
    {
        uint256 cycleNum = getCurrentCycleNum();
        if (cycleNum >= c_maxCycle) {
            return (0, 0);
        }
        end = c_startBlockOffset.add(cycleNum.add(1).mul(c_cycleBlock));
        begin = end.sub(c_duration);
        return (begin, end);
    }

    function isNowInActivity() public view returns (bool) {
        (uint256 begin, uint256 end) = getLatestActivity();
        return block.number >= begin && block.number < end;
    }

    function getCurrentCycleNum() public view returns (uint256) {
        uint256 n = block.number;
        return n.sub(c_startBlockOffset).div(c_cycleBlock);
    }

    function getMinAddPrice() public view returns (uint256) {
        return c_minAddPrice;
    }

    function setMinAddPrice(uint256 _value) public onlyCEO {
        c_minAddPrice = _value;
    }

    function minAddPrice() public view returns (uint256) {
        return c_minAddPrice;
    }

    function _updateBidding() internal {
        uint256 _lastBidding = lastBiddingId;
        for (uint256 i = 0; i < maxBiddingNum; i++) {
            uint256 id = biddingId[i];
            if (id != 0) {
                Auction storage auction = tokenIdToAuction[id];
                if (_hasAuctionByInfo(auction)) {
                    if (_isOnAuction(auction)) {
                        continue;
                    }
                } else {
                    continue;
                }
            }
            // set bidding id
            biddingId[i] = _lastBidding + 1;
            _lastBidding = _lastBidding + 1;
        }
        if (lastBiddingId != _lastBidding) {
            lastBiddingId = _lastBidding;
        }
    }

    function _isBidding(uint256 _id) internal view returns (bool) {
        uint256[] memory list = _biddingIdList();
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == _id) {
                return true;
            }
        }
        return false;
    }

    function _isBiddingNoCheck(uint256 _id) internal view returns (bool) {
        for (uint256 i = 0; i < biddingId.length; i++) {
            if (biddingId[i] == _id) {
                return true;
            }
        }
        return false;
    }

    function _biddingNum() internal view returns (uint256) {
        return maxBiddingNum;
    }

    function _biddingIdList() internal view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](maxBiddingNum);
        uint256 resultIndex = 0;
        uint256 addNum = 1;
        for (uint256 i = 0; i < maxBiddingNum; i++) {
            uint256 id = biddingId[i];
            if (id != 0) {
                Auction storage auction = tokenIdToAuction[id];
                if (_hasAuctionByInfo(auction)) {
                    if (!_isOnAuction(auction)) {
                        id = lastBiddingId + addNum;
                        addNum = addNum + 1;
                    }
                }
            } else {
                id = lastBiddingId + addNum;
                addNum = addNum + 1;
            }
            result[resultIndex] = id;
            resultIndex = resultIndex + 1;
            if (resultIndex == maxBiddingNum) {
                break;
            }
        }
        return result;
    }

    function _getGene(uint256 _id) internal view returns (uint256) {
        GeneEntry storage gene = tokenIdToGene[_id];
        require(gene.used, "target gene not set");
        return gene.gene;
    }

    function _getBiddingGene(uint256 _id) internal view returns (uint256) {
        require(
            _id <= lastBiddingId || _isBidding(_id),
            "FlashSale: id must in bidding"
        );
        require(_id > 0, "FlashSale: id must gt 0");
        return _getGene(_id);
    }

    function _getBiddingGeneNoCheck(uint256 _id)
        internal
        view
        returns (uint256)
    {
        return _getGene(_id);
    }

    function _tokensOfOwnerAuctionOn(address _owner, bool on)
        internal
        view
        returns (uint256[] memory)
    {
        uint256[] memory list = _tokensOfOwnerAuction(_owner);
        uint256 num;
        for (uint256 i = 0; i < list.length; i++) {
            uint256 id = list[i];
            Auction storage auction = tokenIdToAuction[id];
            if (_isOnAuction(auction) == on) {
                num++;
            }
        }
        uint256 resultIndex = 0;
        uint256[] memory result = new uint256[](num);
        for (uint256 i = 0; i < list.length; i++) {
            uint256 id = list[i];
            Auction storage auction = tokenIdToAuction[id];
            if (_isOnAuction(auction) == on) {
                result[resultIndex] = id;
                resultIndex++;
                if (resultIndex >= num) {
                    break;
                }
            }
        }
        return result;
    }

    function _hasAuction(uint256 _id) internal view returns (bool) {
        // Get a reference to the auction struct
        Auction storage auction = tokenIdToAuction[_id];
        return auction.endAt > 0;
    }

    function _hasAuctionByInfo(Auction storage _auction)
        internal
        view
        returns (bool)
    {
        return _auction.endAt > 0;
    }

    /// @dev Computes the price and transfers winnings.
    /// Does NOT transfer ownership of token.
    function _bidFrom(
        address _buyer,
        uint256 _id,
        uint256 _bidAmount
    ) internal whenNotPaused {
        require(isNowInActivity(), "not in activity");

        // Get a reference to the auction struct
        Auction storage auction = tokenIdToAuction[_id];
        if (!_hasAuctionByInfo(auction)) {
            _updateBidding();
            require(
                _isBiddingNoCheck(_id),
                "FlashSale: target id is not in the bidding"
            );
            auction.currentPrice = uint128(c_startingPrice);
            (, uint256 end) = getLatestActivity();
            auction.endAt = uint64(end);
        } else {
            require(
                _isBiddingNoCheck(_id),
                "FlashSale: target id is not in the bidding"
            );
        }

        // Explicitly check that this auction is currently live.
        // (Because of how Ethereum mappings work, we can't just count
        // on the lookup above failing. An invalid _id will just
        // return an auction object that is all zeros.)
        require(
            _isOnAuction(auction),
            "FlashSale: target id is not in the auction"
        );

        // Check that the bid is greater than or equal to the current price
        uint256 minPrice = auction.currentPrice;
        if (auction.buyer != address(0)) {
            minPrice = auction.currentPrice.add(c_minAddPrice);
        }
        require(_bidAmount >= minPrice, "FlashSale: underbid");

        if (auction.buyer != address(0)) {
            require(
                gaeToken.transferFrom(
                    _buyer,
                    auction.buyer,
                    auction.currentPrice
                ),
                "FlashSale: failed to transfer gae token to old buyer"
            );
            _removeTokenFromOwnerEnumerationAuction(auction.buyer, _id);
            uint256 inAmount = _bidAmount.sub(auction.currentPrice);
            require(
                gaeToken.transferFrom(_buyer, address(this), inAmount),
                "FlashSale: failed to transfer gae token to contract"
            );
        } else {
            require(
                gaeToken.transferFrom(_buyer, address(this), _bidAmount),
                "FlashSale: failed to transfer gae token to contract"
            );
        }
        auction.currentPrice = _bidAmount;
        auction.buyer = _buyer;
        _addTokenToOwnerEnumerationAuction(_buyer, _id);
        emit Bid(_id, _buyer, _bidAmount);
    }

    function _takeBid(uint256 _id) internal {
        // Get a reference to the auction struct
        Auction storage auction = tokenIdToAuction[_id];
        address buyer = auction.buyer;
        // Explicitly check that this auction is currently live.
        // (Because of how Ethereum mappings work, we can't just count
        // on the lookup above failing. An invalid _id will just
        // return an auction object that is all zeros.)
        require(_hasAuctionByInfo(auction), "FlashSale: no target auction");
        require(
            !_isOnAuction(auction),
            "FlashSale: target id still in auction"
        );
        require(!auction.taked, "FlashSale: already take");
        require(buyer != address(0), "FlashSale: no buyer");

        alianaContract.createOfficialAliana(_getBiddingGeneNoCheck(_id), buyer);
        auction.taked = true;
        _removeTokenFromOwnerEnumerationAuction(buyer, _id);
        // Tell the world!
        emit TakeBid(_id, buyer, auction.currentPrice);
    }

    // _takeBids LP tokens from Mine.
    function _takeBids(uint32[] memory _tokenIds) internal {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _takeBid(_tokenIds[i]);
        }
    }

    // _takeBids256 LP tokens from Mine.
    function _takeBids256(uint256[] memory _tokenIds) internal {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _takeBid(_tokenIds[i]);
        }
    }

    /// @dev Adds an auction to the list of open auctions. Also fires the
    ///  AuctionCreated event.
    /// @param _tokenId The ID of the token to be put on auction.
    /// @param _auction Auction to add.
    function _addAuction(uint256 _tokenId, Auction memory _auction)
        internal
        whenNotPaused
    {
        // Require that all auctions have a duration of
        // at least one minute. (Keeps our math from getting hairy!)
        require(c_duration >= 1, "FlashSale: duration < 1");

        tokenIdToAuction[_tokenId] = _auction;
    }

    /// @dev Returns true if the NFT is on auction.
    /// @param _auction - Auction to check.
    function _isOnAuction(Auction storage _auction)
        internal
        view
        returns (bool)
    {
        if (_auction.endAt <= block.number || _auction.taked) {
            return false;
        }
        return true;
    }
}

/// @title Clock auction modified for sale of alianas
/// @notice We omit a fallback function to prevent accidental sends to this contract.
contract FlashSale is FlashSaleBase {
    function isFlashSale() public pure returns (bool) {
        return true;
    }

    /// @dev Constructor creates a reference to the NFT ownership contract
    ///  and verifies the owner cut is in the valid range.
    /// @param _alianaAddress - address of a deployed contract implementing
    ///  the Nonfungible Interface.
    /// @param _cut - percent cut the owner takes on each auction, must be
    ///  between 0-10,000.
    constructor(
        IAliana _alianaAddress,
        uint256 _cut,
        IERC20 gaeToken,
        uint256 _cycleBlock
    ) public FlashSaleBase(gaeToken, _cycleBlock) {
        require(_cut <= 10000, "FlashSale: cut too large");
        ownerCut = _cut;

        require(_alianaAddress.isAliana(), "FlashSale: not aliana");

        alianaContract = _alianaAddress;
    }

    /// @dev Returns auction info for an NFT on auction.
    /// @param _tokenId - ID of NFT on auction.
    function getAuction(uint256 _tokenId)
        external
        view
        returns (
            uint256 currentPrice,
            uint256 endAt,
            uint256 gene,
            uint256 lpLabor,
            address buyer,
            bool taked
        )
    {
        Auction storage auction = tokenIdToAuction[_tokenId];
        currentPrice = auction.currentPrice;
        endAt = auction.endAt;
        gene = _getBiddingGeneNoCheck(_tokenId);
        buyer = auction.buyer;
        taked = auction.taked;
        if (!_hasAuctionByInfo(auction)) {
            gene = _getBiddingGene(_tokenId);
            currentPrice = uint128(c_startingPrice);
        }
        lpLabor = alianaContract.geneLpLabor(int256(_tokenId), gene);
    }

    /// @dev Returns the current price of an auction.
    /// @param _tokenId - ID of the token price we are checking.
    function getCurrentPrice(uint256 _tokenId) external view returns (uint256) {
        return tokenIdToAuction[_tokenId].currentPrice;
    }

    function updateBidding() external {
        _updateBidding();
    }

    function biddingNum() external view returns (uint256) {
        return _biddingNum();
    }

    function biddingIdList() external view returns (uint256[] memory) {
        return _biddingIdList();
    }

    function getBiddingGene(uint256 _id) external view returns (uint256) {
        return _getBiddingGene(_id);
    }

    /// @notice Returns a list of all Aliana IDs assigned to an address.
    /// @param _owner The owner whose Kitties we are interested in.
    /// @dev This method MUST NEVER be called by smart contract code. First, it's fairly
    ///  expensive (it walks the entire Aliana array looking for cats belonging to owner),
    ///  but it also returns a dynamic array, which is only supported for web3 calls, and
    ///  not contract-to-contract calls.
    function tokensOfOwnerAuction(address _owner)
        external
        view
        returns (uint256[] memory)
    {
        return _tokensOfOwnerAuction(_owner);
    }

    function tokensOfOwnerAuctionOn(address _owner, bool on)
        external
        view
        returns (uint256[] memory)
    {
        return _tokensOfOwnerAuctionOn(_owner, on);
    }

    /// @dev Updates lastSalePrice if seller is the nft contract
    /// Otherwise, works the same as default bid method.
    function bid(uint32 _tokenId, uint256 _price) external {
        // _bid verifies token ID size
        _bidFrom(msg.sender, _tokenId, _price);
    }

    function takeBid(uint32 _tokenId) external {
        // _bid verifies token ID size
        _takeBid(_tokenId);
    }

    function takeBids(uint32[] calldata _tokenIds) external {
        _takeBids(_tokenIds);
    }

    function setTokenGene(
        uint256[] calldata _tokenIds,
        uint256[] calldata _gene
    ) external onlyCEO {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            tokenIdToGene[_tokenIds[i]].gene = _gene[i];
            tokenIdToGene[_tokenIds[i]].used = true;
        }
    }

    function unsetTokenGene(uint256[] calldata _tokenIds) external onlyCEO {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            tokenIdToGene[_tokenIds[i]].used = false;
        }
    }

    // takeMyBids LP tokens from Mine.
    function takeMyBids() external {
        _takeBids256(_tokensOfOwnerAuctionOn(msg.sender, false));
    }

    // takeBidsOf LP tokens from Mine.
    function takeBidsOf(address addr) external {
        _takeBids256(_tokensOfOwnerAuctionOn(addr, false));
    }

    function receiveApproval(
        address _sender,
        uint256 _value,
        address _tokenContract,
        bytes memory _extraData
    ) public {
        require(_value > 0, "FlashSale: approval zero");
        uint256 action;
        assembly {
            action := mload(add(_extraData, 0x20))
        }
        require(action == 2, "FlashSale: unknow action");
        if (action == 2) {
            // buy
            require(
                _tokenContract == address(gaeToken),
                "FlashSale: approval and want buy a aliana, but used token isn't GFT"
            );
            uint256 tokenId;
            uint256 price;
            assembly {
                tokenId := mload(add(_extraData, 0x40))
                price := mload(add(_extraData, 0x60))
            }
            _bidFrom(_sender, tokenId, price);
        }
    }
}
