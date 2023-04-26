pragma solidity >=0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./interfaces/IAliumCollectible.sol";

contract FarmingTicketToken is IAliumCollectible, ERC721, Ownable {
    Counters.Counter private _tokenIdTracker;

    constructor()
        ERC721("Alium Farming Ticket Token", "ALMFTT")
        public
    {
        //
    }

    function mint(address _to) external override onlyOwner {
        Counters.increment(_tokenIdTracker);
        _mint(_to, Counters.current(_tokenIdTracker));
    }

    /**
     * @dev See {ERC71-_exists}.
     */
    function exists(uint256 _tokenId) public view returns (bool) {
        return _exists(_tokenId);
    }
}