// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../WrapDoNFT.sol";
import "../BaseDoNFT.sol";
import "./IDCL.sol";

contract DclDoNFT is WrapDoNFT{
    using EnumerableSet for EnumerableSet.UintSet;
    constructor(address address_,string memory name_, string memory symbol_) {
        super.init(address_, name_, symbol_);
    }
    
    function checkIn(address to,uint256 tokenId,uint256 durationId) public override virtual{
        BaseDoNFT.checkIn(to,tokenId,durationId);
        DoNftInfo storage info = doNftMapping[tokenId];
        IDCL(oNftAddress).setUpdateOperator(info.oid, to);
    }

    

}
