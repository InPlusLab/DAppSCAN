// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./OwnableContract.sol";

interface IBaseDoNFT is IERC721Receiver {
    struct Duration{
        uint64 start; 
        uint64 end;
    }

    struct DoNftInfo {
        uint256 oid;
        uint64 nonce;
        EnumerableSet.UintSet durationList;
    }
    event MintWNft(address opreator,address to,uint256 oid,uint256 tokenId);

    event MetadataUpdate(uint256 tokenId);

    event DurationUpdate(uint256 durationId,uint256 tokenId,uint64 start,uint64 end);

    event DurationBurn(uint256[] durationIdList);

    event CheckIn(address opreator,address to,uint256 tokenId,uint256 durationId);

    function init(address address_,string memory name_, string memory symbol_) external;

    function isWrap() external pure returns(bool);

    function mintWNft(uint256 oid) external returns(uint256 tid);

    function mint(uint256 tokenId,uint256 durationId,uint64 start,uint64 end,address to) external returns(uint256 tid);

    function setMaxDuration(uint64 v) external;

    function getDurationIdList(uint256 tokenId) external view returns(uint256[] memory);

    function getDurationListLength(uint256 tokenId) external view returns(uint256);

    function getDoNftInfo(uint256 tokenId) external view returns(uint256 oid, uint256[] memory durationIds,uint64[] memory starts,uint64[] memory ends,uint64 nonce);

    function getNonce(uint256 tokenId) external view returns(uint64);

    function getDuration(uint256 durationId) external view returns(uint64 start, uint64 end);

    function getDuration(uint256 tokenId,uint256 index) external view returns(uint256 durationId,uint64 start, uint64 end);

    function getWNftId(uint256 originalNftId) external view returns(uint256);

    function isValidNow(uint256 tokenId) external view returns(bool isValid);

    function getOrignalNftAddress() external view returns(address);

    function checkIn(address to,uint256 tokenId,uint256 durationId) external;

    
}
