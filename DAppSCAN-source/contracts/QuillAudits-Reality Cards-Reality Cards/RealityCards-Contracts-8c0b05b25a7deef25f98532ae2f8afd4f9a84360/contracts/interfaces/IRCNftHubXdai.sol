pragma solidity 0.5.13;

interface IRCNftHubXdai {
    function ownerOf(uint256) external view returns (address);
    function tokenURI(uint256) external view returns (string memory);
    function addMarket(address) external returns (bool);
    function mintNft(address,uint256,string calldata) external returns (bool);
    function transferNft(address,address,uint256) external returns (bool);
    function upgradeCard(address,uint256) external returns (bool);
}