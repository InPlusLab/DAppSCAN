pragma solidity ^0.5.0;

/// @title SEKRETOOOO
contract IAuction {
    function isAuction() public returns (bool);

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
        );

    function biddingIdList() external view returns (uint256[] memory);

    function tokensOfOwnerAuctionOn(address _owner, bool on)
        external
        view
        returns (uint256[] memory);

    function takeBid(uint256 _tokenId) external;
}
