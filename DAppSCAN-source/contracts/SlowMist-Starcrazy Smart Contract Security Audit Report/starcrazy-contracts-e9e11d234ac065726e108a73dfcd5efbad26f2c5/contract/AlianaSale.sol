pragma solidity ^0.5.0;

import "./aliana/GFAccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./aliana/IAliana.sol";

contract AlianaSale is GFAccessControl {
    using SafeMath for uint256;

    // The gae TOKEN
    IERC20 public gaeToken;
    IAliana public aliana;

    // Mapping from owner to list of owned token IDs
    mapping(address => uint256[]) private _ownedTokensSale;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndexSale;

    // Array with all token ids, used for enumeration
    uint256[] private _allTokensSale;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndexSale;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => AlianaSaleInfo) private _allSaleAlianaInfo;

    // Cut owner takes on each auction, measured in basis points (1/100 of a percent).
    // Values 0-10,000 map to 0%-100%
    uint256 public ownerCutSale;
    uint256 public cutedSaleBalance;

    // Info of each sale aliana.
    struct AlianaSaleInfo {
        uint256 tokenId;
        uint256 beginBlock;
        uint256 price;
        address seller;
    }

    event CreateAlianaSale(
        address indexed seller,
        uint256 indexed tokenId,
        uint256 price
    );
    event CancelAlianaSale(address indexed seller, uint256 tokenId);
    event BuySaleAliana(
        address indexed seller,
        address indexed buyer,
        uint256 indexed tokenId
    );

    constructor(IERC20 _gaeToken, IAliana _alianaAddr) public {
        require(_alianaAddr.isAliana(), "AlianaSale: isAliana false");
        gaeToken = _gaeToken;
        aliana = _alianaAddr;
        ownerCutSale = 300;
    }

    /// @dev Update the value of ownerCutSale, can only be called by the CEO.
    function setOwnerCutSale(uint256 num) external onlyCEO {
        require(num <= 10000, "AlianaSale: num not valid");
        ownerCutSale = num;
    }

    function withdrawOwnerCutSale(uint256 num) external onlyCLevel {
        require(num <= cutedSaleBalance, "AlianaSale: num <= cutedSaleBalance");

        require(
            gaeToken.transferFrom(address(this), msg.sender, num),
            "AlianaSale: failed to transfer gae token"
        );

        cutedSaleBalance = cutedSaleBalance.sub(num);
    }

    /// @notice Returns all the relevant information about a specific aliana.
    /// @param _tokenId The ID of the aliana of interest.
    function getAlianaSaleInfo(uint256 _tokenId)
        external
        view
        returns (
            uint256 beginBlock,
            uint256 price,
            address seller
        )
    {
        AlianaSaleInfo storage info = _allSaleAlianaInfo[_tokenId];
        beginBlock = info.beginBlock;
        price = info.price;
        seller = info.seller;
        if (!_isOnSale(info)) {
            beginBlock = 0;
            price = 0;
            seller = address(0);
        }
    }

    function createAlianaSale(uint256 _tokenId, uint256 _price)
        external
        whenNotPaused
    {
        _createAlianaSaleFrom(msg.sender, _tokenId, _price);
    }

    function _createAlianaSaleFrom(
        address _from,
        uint256 _tokenId,
        uint256 _price
    ) internal whenNotPaused {
        require(_price > 0, "AlianaSale: price can't be 0");
        require(
            aliana.ownerOf(_tokenId) == _from,
            "AlianaSale: must be the owner"
        );

        aliana.transferFrom(address(_from), address(this), _tokenId);

        _addTokenToOwnerEnumerationSale(_from, _tokenId);

        _addTokenToAllTokensEnumerationSale(_tokenId);

        AlianaSaleInfo storage info = _allSaleAlianaInfo[_tokenId];
        info.tokenId = _tokenId;
        info.beginBlock = block.number;
        info.price = _price;
        info.seller = _from;

        emit CreateAlianaSale(_from, _tokenId, _price);
    }

    function adminCancelAlianaSales(uint256[] memory _tokenIds)
        public
        onlyCLevel
    {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _tokenId = _tokenIds[i];
            AlianaSaleInfo storage info = _allSaleAlianaInfo[_tokenId];
            if (_isOnSale(info)) {
                aliana.transferFrom(
                    address(this),
                    address(info.seller),
                    _tokenId
                );
                _burnSale(info.seller, _tokenId);
                emit CancelAlianaSale(info.seller, _tokenId);
            }
        }
    }

    function cancelAlianaSale(uint256 _tokenId) external {
        _cancelAlianaSaleFrom(msg.sender, _tokenId);
    }

    function _cancelAlianaSaleFrom(address _from, uint256 _tokenId) internal {
        AlianaSaleInfo storage info = _allSaleAlianaInfo[_tokenId];
        require(_isOnSale(info), "AlianaSale: target token not on sale");
        address seller = info.seller;
        require(_from == seller, "AlianaSale: you're not the seller");

        aliana.transferFrom(address(this), address(info.seller), _tokenId);

        _burnSale(info.seller, _tokenId);

        emit CancelAlianaSale(info.seller, _tokenId);
    }

    function buySaleAliana(uint256 _tokenId) external whenNotPaused {
        _buySaleAlianaFrom(msg.sender, _tokenId);
    }

    function _buySaleAlianaFrom(address buyer, uint256 _tokenId)
        internal
        whenNotPaused
    {
        AlianaSaleInfo storage info = _allSaleAlianaInfo[_tokenId];
        require(_isOnSale(info), "AlianaSale: target token not on sale");

        require(
            gaeToken.transferFrom(buyer, address(this), info.price),
            "AlianaSale: failed to transfer gae token to contract"
        );

        uint256 auctioneerCut = _computeCutSale(info.price);
        uint256 sellerGet = info.price - auctioneerCut;
        cutedSaleBalance = cutedSaleBalance.add(auctioneerCut);

        require(
            gaeToken.transferFrom(address(this), info.seller, sellerGet),
            "AlianaSale: failed to transfer gae token to seller"
        );

        aliana.transferFrom(address(this), address(buyer), _tokenId);

        emit BuySaleAliana(info.seller, buyer, _tokenId);
        _burnSale(info.seller, _tokenId);
    }

    /// @dev Computes owner's cut of a sale.
    /// @param _price - Sale price of NFT.
    function _computeCutSale(uint256 _price) internal view returns (uint256) {
        // NOTE: We don't use SafeMath (or similar) in this function because
        //  all of our entry functions carefully cap the maximum values for
        //  currency (at 128-bits), and ownerCut <= 10000 (see the require()
        //  statement in the ClockAuction constructor). The result of this
        //  function is always guaranteed to be <= _price.
        return (_price * ownerCutSale) / 10000;
    }

    function _burnSale(address _seller, uint256 _tokenId) internal {
        _removeTokenFromOwnerEnumerationSale(_seller, _tokenId);
        // Since _tokenId will be deleted, we can clear its slot in _ownedTokensIndex to trigger a gas refund
        _ownedTokensIndexSale[_tokenId] = 0;
        _removeTokenFromAllTokensEnumerationSale(_tokenId);

        AlianaSaleInfo storage info = _allSaleAlianaInfo[_tokenId];
        info.beginBlock = 0;
        info.seller = address(0);
        info.price = 0;
    }

    /// @dev Returns true if the NFT is on sale.
    /// @param _info - Auction to check.
    function _isOnSale(AlianaSaleInfo storage _info)
        internal
        view
        returns (bool)
    {
        return (_info.beginBlock > 0);
    }

    function totalSale() public view returns (uint256) {
        return _allTokensSale.length;
    }

    /**
     * @dev Gets the list of token IDs of the sale.
     * @return uint256[] List of token IDs sale.
     */
    function allTokensSale() external view returns (uint256[] memory tokenIds) {
        return _allTokensSale;
    }

    /**
     * @dev Gets the list of token IDs of the sale.
     * @return uint256[] List of token IDs sale.
     */
    function listTokensSale(uint256 _skip, uint256 _limit)
        external
        view
        returns (uint256[] memory tokenIds)
    {
        uint256 totalCount = totalSale();
        if (_limit == 0 || _skip >= totalCount) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256 tokenCount = _limit;
            if (_skip.add(_limit) > totalCount) {
                tokenCount = totalCount - _skip;
            }
            uint256 end = _skip.add(tokenCount);
            uint256[] memory result = new uint256[](tokenCount);
            uint256 resultIndex = 0;

            // We count on the fact that all cats have IDs starting at 1 and increasing
            // sequentially up to the totalCat count.
            uint256 i;

            for (i = _skip; i < end; i++) {
                result[resultIndex] = _allTokensSale[i];
                resultIndex++;
            }

            return result;
        }
    }

    /// @notice Returns a list of all Aliana IDs assigned to an address.
    /// @param _owner The owner whose Kitties we are interested in.
    /// @dev This method MUST NEVER be called by smart contract code. First, it's fairly
    ///  expensive (it walks the entire Aliana array looking for cats belonging to owner),
    ///  but it also returns a dynamic array, which is only supported for web3 calls, and
    ///  not contract-to-contract calls.
    function tokensOfOwnerSale(address _owner)
        external
        view
        returns (uint256[] memory ownerTokens)
    {
        return _tokensOfOwnerSale(_owner);
    }

    /**
     * @dev Gets the list of token IDs of the requested owner.
     * @param owner address owning the tokens
     * @return uint256[] List of token IDs owned by the requested address
     */
    function _tokensOfOwnerSale(address owner)
        internal
        view
        returns (uint256[] storage)
    {
        return _ownedTokensSale[owner];
    }

    /**
     * @dev Private function to add a token to this extension's ownership-tracking data structures.
     * @param to address representing the new owner of the given token ID
     * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
     */
    function _addTokenToOwnerEnumerationSale(address to, uint256 tokenId)
        private
    {
        _ownedTokensIndexSale[tokenId] = _ownedTokensSale[to].length;
        _ownedTokensSale[to].push(tokenId);
    }

    /**
     * @dev Private function to add a token to this extension's token tracking data structures.
     * @param tokenId uint256 ID of the token to be added to the tokens list
     */
    function _addTokenToAllTokensEnumerationSale(uint256 tokenId) private {
        _allTokensIndexSale[tokenId] = _allTokensSale.length;
        _allTokensSale.push(tokenId);
    }

    /**
     * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
     * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
     * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
     * This has O(1) time complexity, but alters the order of the _ownedTokens array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
     */
    function _removeTokenFromOwnerEnumerationSale(address from, uint256 tokenId)
        private
    {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _ownedTokensSale[from].length.sub(1);
        uint256 tokenIndex = _ownedTokensIndexSale[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokensSale[from][lastTokenIndex];

            _ownedTokensSale[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndexSale[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        _ownedTokensSale[from].length--;

        // Note that _ownedTokensIndex[tokenId] hasn't been cleared: it still points to the old slot (now occupied by
        // lastTokenId, or just over the end of the array if the token was the last one).
    }

    /**
     * @dev Private function to remove a token from this extension's token tracking data structures.
     * This has O(1) time complexity, but alters the order of the _allTokens array.
     * @param tokenId uint256 ID of the token to be removed from the tokens list
     */
    function _removeTokenFromAllTokensEnumerationSale(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokensSale.length.sub(1);
        uint256 tokenIndex = _allTokensIndexSale[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokensSale[lastTokenIndex];

        _allTokensSale[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndexSale[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        _allTokensSale.length--;
        _allTokensIndexSale[tokenId] = 0;
    }

    function receiveApproval(
        address _sender,
        uint256 _value,
        address _tokenContract,
        bytes memory _extraData
    ) public {
        require(_value >= 0, "AlianaSale: approval negative");
        uint256 action;
        assembly {
            action := mload(add(_extraData, 0x20))
        }
        require(action == 1 || action == 2, "AlianaSale: unknow action");
        if (action == 1) {
            // buy
            require(
                _tokenContract == address(gaeToken),
                "AlianaSale: approval and want buy a aliana, but used token isn't GFT"
            );
            uint256 tokenId;
            assembly {
                tokenId := mload(add(_extraData, 0x40))
            }
            _buySaleAlianaFrom(_sender, tokenId);
        } else if (action == 2) {
            // sale
            require(
                _tokenContract == address(aliana),
                "AlianaSale: approval and want sale a aliana, but used token isn't Aliana"
            );
            uint256 tokenId;
            uint256 price;
            assembly {
                tokenId := mload(add(_extraData, 0x40))
                price := mload(add(_extraData, 0x60))
            }
            _createAlianaSaleFrom(_sender, tokenId, price);
        }
    }
}
