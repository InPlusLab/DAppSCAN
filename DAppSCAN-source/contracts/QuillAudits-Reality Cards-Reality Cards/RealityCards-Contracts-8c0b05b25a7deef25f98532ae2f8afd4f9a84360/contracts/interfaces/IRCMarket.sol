pragma solidity 0.5.13;
pragma experimental ABIEncoderV2;

interface IRCMarket {

    function isMarket() external view returns (bool);
    function sponsor() external payable;

    function initialize(
        uint256 _mode, 
        uint32[] calldata _timestamps,
        uint256 _numberOfTokens,
        uint256 _totalNftMintCount,
        address _artistAddress,
        address _affiliateAddress,
        address[] calldata _cardAffiliateAddresses,
        address _marketCreatorAddress
    ) external; 

    function tokenURI(uint256) external view returns (string memory);  
    function ownerOf(uint256 tokenId) external view returns  (address);
    function state() external view returns (uint256);
    function setWinner(uint256) external;

}
