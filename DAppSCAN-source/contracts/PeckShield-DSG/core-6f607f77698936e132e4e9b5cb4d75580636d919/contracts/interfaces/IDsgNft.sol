// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../libraries/LibPart.sol";

interface IDsgNft is IERC721 {

    function mint(
        address to, string memory nftName, uint quality, uint256 power, string memory res, address author
    ) external returns(uint256 tokenId);

    function burn(uint256 tokenId) external;

    function getFeeToken() external view returns (address);

    function getNft(uint256 id) external view returns (LibPart.NftInfo memory);

    function getRoyalties(uint256 tokenId) external view returns (LibPart.Part[] memory);

    function sumRoyalties(uint256 tokenId) external view returns(uint256);

    function upgradeNft(uint256 nftId, uint256 materialNftId) external;

    function getPower(uint256 tokenId) external view returns (uint256);

    function getLevel(uint256 tokenId) external view returns (uint256);
}