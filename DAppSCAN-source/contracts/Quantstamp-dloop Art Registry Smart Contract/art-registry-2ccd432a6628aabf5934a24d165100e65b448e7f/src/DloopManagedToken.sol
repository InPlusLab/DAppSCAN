pragma solidity 0.5.17;

import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "./DloopGovernance.sol";

contract DloopManagedToken is ERC721, DloopGovernance {
    mapping(uint256 => bool) private _managedMap;

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public {
        require(!isManaged(tokenId), "token is managed");
        super.safeTransferFrom(from, to, tokenId, _data);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(!isManaged(tokenId), "token is managed");
        super.transferFrom(from, to, tokenId);
    }

    function isManaged(uint256 tokenId) public view returns (bool) {
        require(super._exists(tokenId), "tokenId does not exist");
        return _managedMap[tokenId];
    }

    function _setManaged(uint256 tokenId, bool managed) internal {
        require(super._exists(tokenId), "tokenId does not exist");
        _managedMap[tokenId] = managed;
    }
}
