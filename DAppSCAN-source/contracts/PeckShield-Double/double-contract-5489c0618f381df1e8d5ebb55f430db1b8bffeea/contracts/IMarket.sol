// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6 <0.9.0;

interface IMarket {

    struct Lending {
        address lender;
        address nftAddress;
        uint256 nftId;
        uint256 pricePerSecond;
        uint64 maxEndTime;
        uint64 minDuration;
        uint64 nonce;
    }
    struct Renting {
        address payable renterAddress;
        uint64 startTime;
        uint64 endTime;
    }

    struct Royalty {
        uint256 fee;
        uint256 balance;
        address payable beneficiary;
    }

    struct Credit{
        mapping(uint256=>Lending) lendingMap;
    }

    event OnLent(address lender,address nftAddress,uint256 nftId,uint64 maxEndTime,uint64 minDuration,uint256 pricePerSecond);
    event OffLent(address lender,address nftAddress,uint256 nftId);
    event MakeDeal(address renter,address lender,address nftAddress,uint256 nftId,uint64 startTime,uint64 endTime,uint256 pricePerSecond,uint256 newId);
    
    function mintWNftAndOnLent(
        address resolverAddress,
        uint256 oNftId,
        uint64 maxEndTime,
        uint64 minDuration,
        uint256 pricePerSecond
    ) external ;

    function onLent(
        address nftAddress,
        uint256 nftId,
        uint64 maxEndTime,
        uint64 minDuration,
        uint256 pricePerSecond
    ) external;

    function offLent(address nftAddress,uint256 nftId) external;

    function getLent(address nftAddress,uint256 nftId) external view returns (Lending memory lenting);
    
    function makeDeal(address nftAddress,uint256 tokenId,uint256 durationId,uint64 startTime,uint64 endTime) external payable returns(uint256 tid);

    function makeDealNow(address nftAddress,uint256 tokenId,uint256 durationId,uint64 duration) external payable returns(uint256 tid);

    function setFee(uint256 fee) external;

    function setMarketBeneficiary(address payable beneficiary) external;

    function claimFee() external;

    function setRoyalty(address nftAddress,uint256 fee) external;

    function setRoyaltyBeneficiary(address nftAddress,address payable beneficiary) external;

    function claimRoyalty(address nftAddress) external;

    function isOnLent(address nftAddress,uint256 nftId) external view returns (bool);

}