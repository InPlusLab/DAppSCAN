// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./BaseDoNFT.sol";

contract VirtualDoNFT is BaseDoNFT{

    function mintWNft(uint256 oid) public nonReentrant override virtual returns(uint256 tid) {
        require(oid2Wid[oid] == 0, "already warped");
        require(onlyApprovedOrOwner(tx.origin,oNftAddress,oid) || onlyApprovedOrOwner(msg.sender,oNftAddress,oid));
        address owner = ERC721(oNftAddress).ownerOf(oid);
        tid = newDoNft(oid,uint64(block.timestamp),type(uint64).max);
        oid2Wid[oid] = tid;
        emit MintWNft(tx.origin,owner,oid, tid);
    }

    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        if(isWNft(tokenId)){
            return ERC721(oNftAddress).ownerOf(tokenId);
        }
        return ERC721(address(this)).ownerOf(tokenId);
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override virtual {
        require(!isWNft(tokenId),"cannot transfer wNft");
        ERC721._transfer(from, to, tokenId);
    }

}
