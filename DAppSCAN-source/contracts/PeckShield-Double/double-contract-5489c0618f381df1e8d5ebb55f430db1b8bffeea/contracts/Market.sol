// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IMarket.sol";
import "./OwnableContract.sol";
import "./IBaseDoNFT.sol";
//SWC-131-Presence of unused variables: L9-L18
contract Market is OwnableContract,ReentrancyGuard,IMarket{
    uint64 constant private E5 = 1e5;
    uint64 constant private SECONDS_IN_DAY = 86400;
    mapping(address=>Credit) internal creditMap;
    mapping(address=>Royalty) internal royaltyMap;
    uint256 public fee;
    uint256 public balanceOfFee;
    address payable public beneficiary;
    string private _name;

    constructor(string memory name_){
        _name = name_;
    }

    modifier onlyApprovedOrOwner(address spender,address nftAddress,uint256 tokenId) {
        address owner = ERC721(nftAddress).ownerOf(tokenId);
        require(owner != address(0),"ERC721: operator query for nonexistent token");
        require(spender == owner || ERC721(nftAddress).getApproved(tokenId) == spender || ERC721(nftAddress).isApprovedForAll(owner, spender));
        _;
    }
    function getName()public view returns(string memory){
        return _name;
    }

    function mintWNftAndOnLent (
        address doNftAddress,
        uint256 oNftId,
        uint64 maxEndTime,
        uint64 minDuration,
        uint256 pricePerSecond
    ) public nonReentrant onlyApprovedOrOwner(msg.sender,IBaseDoNFT(doNftAddress).getOrignalNftAddress(),oNftId){
        uint256 nftId = IBaseDoNFT(doNftAddress).mintWNft(oNftId);
        onLent(doNftAddress, nftId, maxEndTime,minDuration, pricePerSecond);
    }

    function onLent(
        address nftAddress,
        uint256 nftId,
        uint64 maxEndTime,
        uint64 minDuration,
        uint256 pricePerSecond
    ) public onlyApprovedOrOwner(msg.sender,nftAddress,nftId){
        require(IERC165(nftAddress).supportsInterface(type(IBaseDoNFT).interfaceId),"not doNFT");
        address owner = ERC721(nftAddress).ownerOf(nftId);
        Lending storage lending = creditMap[nftAddress].lendingMap[nftId];
        lending.lender = owner;
        lending.nftAddress = nftAddress;
        lending.nftId = nftId;
        lending.maxEndTime = maxEndTime;
        lending.minDuration = minDuration;
        lending.pricePerSecond = pricePerSecond;
        lending.nonce = IBaseDoNFT(nftAddress).getNonce(nftId);
        emit OnLent(owner,nftAddress, nftId, maxEndTime,minDuration,pricePerSecond);
    }

    function offLent(address nftAddress, uint256 nftId) public onlyApprovedOrOwner(msg.sender,nftAddress,nftId){
        delete creditMap[nftAddress].lendingMap[nftId];
        emit OffLent(msg.sender,nftAddress, nftId);
    }

    function getLent(address nftAddress,uint256 nftId) public view returns (Lending memory lenting){
        lenting = creditMap[nftAddress].lendingMap[nftId];
    }
    
    
    function makeDeal(address nftAddress,uint256 tokenId,uint256 durationId,uint64 startTime,uint64 endTime) public nonReentrant payable virtual returns(uint256 tid){
        Lending storage lending = creditMap[nftAddress].lendingMap[tokenId];
        require(isOnLent(nftAddress,tokenId),"not on lend");
        require(endTime <= lending.maxEndTime,"endTime > lending.maxEndTime ");
        (uint64 dStart,uint64 dEnd) = IBaseDoNFT(nftAddress).getDuration(durationId);
        if(!(startTime == block.timestamp && endTime== dEnd)){
            require((endTime-startTime) >= lending.minDuration,"duration < minDuration");
        }
        distributePayment(nftAddress, tokenId, startTime, endTime);
        tid = IBaseDoNFT(nftAddress).mint(tokenId, durationId, startTime, endTime, msg.sender);
        emit MakeDeal(msg.sender, lending.lender, lending.nftAddress, lending.nftId, startTime, endTime, lending.pricePerSecond,tid);
    }

    function makeDealNow(address nftAddress,uint256 tokenId,uint256 durationId,uint64 duration) public payable virtual returns(uint256 tid){
        tid = makeDeal(nftAddress, tokenId, durationId, uint64(block.timestamp), uint64(block.timestamp + duration));
    }

    function distributePayment(address nftAddress,uint256 nftId,uint64 startTime,uint64 endTime) internal returns (uint256 totolPrice,uint256 leftTotolPrice,uint256 curFee,uint256 curRoyalty){
        Lending storage lending = creditMap[nftAddress].lendingMap[nftId];
        totolPrice = lending.pricePerSecond * (endTime - startTime);
        curFee = totolPrice * fee / E5;
        curRoyalty = totolPrice * royaltyMap[nftAddress].fee / E5;
        royaltyMap[nftAddress].balance += curRoyalty;
        balanceOfFee += curFee;
        leftTotolPrice = totolPrice - curFee - curRoyalty;
        require(msg.value >= totolPrice);
        payable(ERC721(nftAddress).ownerOf(nftId)).transfer(leftTotolPrice);

        if (msg.value > totolPrice) {
           payable(msg.sender).transfer(msg.value - totolPrice);
        }
    }

    function setFee(uint256 fee_) public onlyAdmin{
        fee = fee_;
    }

    function setMarketBeneficiary(address payable beneficiary_) public onlyAdmin{
        beneficiary = beneficiary_;
    }

    function claimFee() public{
        require(msg.sender==beneficiary,"not beneficiary");
        beneficiary.transfer(balanceOfFee);
        balanceOfFee = 0;
    }

    function setRoyalty(address nftAddress,uint256 fee_) public onlyAdmin{
        royaltyMap[nftAddress].fee = fee_;
    }

    function setRoyaltyBeneficiary(address nftAddress,address payable beneficiary_) public onlyAdmin{
        royaltyMap[nftAddress].beneficiary = beneficiary_;
    }

    function claimRoyalty(address nftAddress) public{
        royaltyMap[nftAddress].beneficiary.transfer(royaltyMap[nftAddress].balance);
        royaltyMap[nftAddress].balance = 0;
    }

    function isOnLent(address nftAddress,uint256 nftId) public view returns (bool){
        Lending storage lending = creditMap[nftAddress].lendingMap[nftId];
        return  lending.nftId > 0 && 
                lending.maxEndTime > block.timestamp && 
                lending.nonce == IBaseDoNFT(nftAddress).getNonce(nftId);
    }

}