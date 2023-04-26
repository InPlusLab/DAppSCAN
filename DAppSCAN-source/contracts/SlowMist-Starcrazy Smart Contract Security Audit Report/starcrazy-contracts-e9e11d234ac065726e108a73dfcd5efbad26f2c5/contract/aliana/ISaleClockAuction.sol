pragma solidity ^0.5.0;

/// @title SEKRETOOOO
contract ISaleClockAuction {
    /// @dev simply a boolean to indicate this is the contract we expect to be
    function isAuction() public pure returns (bool);

    function createAuction(
        uint256 _tokenId,
        uint256 _startingPrice,
        uint256 _endingPrice,
        uint256 _duration,
        address _seller
    ) external;

    function claimTokens(address token_) public;
}
