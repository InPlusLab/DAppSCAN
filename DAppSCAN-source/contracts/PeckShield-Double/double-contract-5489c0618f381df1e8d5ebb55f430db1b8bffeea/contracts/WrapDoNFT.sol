// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./IWrapDoNFT.sol";
import "./BaseDoNFT.sol";

contract WrapDoNFT is BaseDoNFT,IWrapDoNFT{
    using EnumerableSet for EnumerableSet.UintSet;

    function mintWNft(uint256 oid) public override returns(uint256 tid){
        require(oid2Wid[oid] == 0, "already warped");
        require(onlyApprovedOrOwner(tx.origin,oNftAddress,oid) || onlyApprovedOrOwner(msg.sender,oNftAddress,oid));
        address lastOwner = ERC721(oNftAddress).ownerOf(oid);
        ERC721(oNftAddress).safeTransferFrom(lastOwner, address(this), oid);
        tid = mintDoNft(lastOwner,oid,uint64(block.timestamp),type(uint64).max);
        oid2Wid[oid] = tid;
        emit MintWNft(tx.origin,lastOwner,oid,tid);
    }
    
    function couldRedeem(uint256 tokenId,uint256[] calldata durationIds) public view returns(bool) {
        require(isWNft(tokenId) , "not wNFT") ;
        DoNftInfo storage info = doNftMapping[tokenId];
        Duration storage duration = durationMapping[durationIds[0]];
        if(duration.start > block.timestamp){
            return false;
        }
        uint64 lastEndTime = duration.end;
        for (uint256 index = 1; index < durationIds.length; index++) {
            require(info.durationList.contains(durationIds[index]),"out of bundle");
            duration = durationMapping[durationIds[index]];
            if(lastEndTime+1 == duration.start){
                lastEndTime = duration.end;
            }
        }
        return lastEndTime == type(uint64).max;
        
        
    }
    
    function redeem(uint256 tokenId,uint256[] calldata durationIds) public{
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        require(couldRedeem(tokenId, durationIds),"cannot redeem");
        DoNftInfo storage info = doNftMapping[tokenId];
        ERC721(oNftAddress).safeTransferFrom(address(this), ownerOf(tokenId), info.oid);
        _burnWNft(tokenId);
        emit Redeem(info.oid,tokenId);
    }

    function isWrap() public pure override returns(bool){
        return true;
    }


}
