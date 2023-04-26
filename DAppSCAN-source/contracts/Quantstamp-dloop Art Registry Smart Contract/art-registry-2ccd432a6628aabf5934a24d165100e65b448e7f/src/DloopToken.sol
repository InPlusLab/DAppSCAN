pragma solidity 0.5.17;

import "openzeppelin-solidity/contracts/token/ERC721/ERC721Enumerable.sol";
import "./DloopMintable.sol";
import "./CustomERC721Metadata.sol";

contract DloopToken is CustomERC721Metadata, ERC721Enumerable, DloopMintable {
    constructor(string memory baseURI)
        public
        CustomERC721Metadata("dloop Art Registry", "DART", baseURI)
    {
        // solhint-disable-previous-line no-empty-blocks
    }

    function setBaseURI(string memory baseURI)
        public
        onlyMinter
        returns (bool)
    {
        super._setBaseURI(baseURI);
        return true;
    }
}
