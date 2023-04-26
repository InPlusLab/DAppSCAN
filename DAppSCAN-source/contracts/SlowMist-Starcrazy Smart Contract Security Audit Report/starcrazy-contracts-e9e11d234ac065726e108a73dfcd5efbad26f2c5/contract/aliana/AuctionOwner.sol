pragma solidity ^0.5.0;

import "../math/SafeMath.sol";

contract AuctionOwner {
    using SafeMath for uint256;

    // Mapping from owner to list of owned token IDs
    mapping(address => uint256[]) private _ownedTokensAuction;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndexAuction;

    /**
     * @dev Gets the list of token IDs of the requested owner.
     * @param owner address owning the tokens
     * @return uint256[] List of token IDs owned by the requested address
     */
    function _tokensOfOwnerAuction(address owner)
        internal
        view
        returns (uint256[] storage)
    {
        return _ownedTokensAuction[owner];
    }

    /**
     * @dev Private function to add a token to this extension's ownership-tracking data structures.
     * @param to address representing the new owner of the given token ID
     * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
     */
    function _addTokenToOwnerEnumerationAuction(address to, uint256 tokenId)
        internal
    {
        _ownedTokensIndexAuction[tokenId] = _ownedTokensAuction[to].length;
        _ownedTokensAuction[to].push(tokenId);
    }

    /**
     * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
     * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
     * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
     * This has O(1) time complexity, but alters the order of the _ownedTokens array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
     */
    function _removeTokenFromOwnerEnumerationAuction(
        address from,
        uint256 tokenId
    ) internal {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _ownedTokensAuction[from].length.sub(1);
        uint256 tokenIndex = _ownedTokensIndexAuction[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokensAuction[from][lastTokenIndex];

            _ownedTokensAuction[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndexAuction[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        _ownedTokensAuction[from].length--;

        // Note that _ownedTokensIndex[tokenId] hasn't been cleared: it still points to the old slot (now occupied by
        // lastTokenId, or just over the end of the array if the token was the last one).
    }
}
