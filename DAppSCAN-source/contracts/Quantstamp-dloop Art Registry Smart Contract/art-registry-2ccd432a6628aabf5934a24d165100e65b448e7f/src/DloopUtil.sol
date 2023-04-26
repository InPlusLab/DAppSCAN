pragma solidity 0.5.17;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

contract DloopUtil {
    uint256 internal constant MAX_DATA_LENGTH = 4096;
    uint256 internal constant MIN_DATA_LENGTH = 1;

    struct Data {
        bytes32 dataType;
        bytes data;
    }

    function createTokenId(
        uint64 artworkId,
        uint16 editionNumber,
        uint8 artistProofNumber
    ) public pure returns (uint256) {
        require(artworkId > 0, "artworkId must be positive");
        require(
            editionNumber > 0 || artistProofNumber > 0,
            "one of editionNumber or artistProofNumber must be positive"
        );
        require(
            !(editionNumber != 0 && artistProofNumber != 0),
            "one of editionNumber or artistProofNumber must be zero"
        );

        uint256 tokenId = artworkId;
        tokenId = tokenId << 16;
        tokenId = SafeMath.add(tokenId, editionNumber);
        tokenId = tokenId << 8;
        tokenId = SafeMath.add(tokenId, artistProofNumber);

        return tokenId;
    }

    function splitTokenId(uint256 tokenId)
        public
        pure
        returns (
            uint64 artworkId,
            uint16 editionNumber,
            uint8 artistProofNumber
        )
    {
        artworkId = uint64(tokenId >> 24);
        editionNumber = uint16(tokenId >> 8);
        artistProofNumber = uint8(tokenId);

        require(artworkId > 0, "artworkId must be positive");
        require(
            editionNumber > 0 || artistProofNumber > 0,
            "one of editionNumber or artistProofNumber must be positive"
        );
        require(
            !(editionNumber != 0 && artistProofNumber != 0),
            "one of editionNumber or artistProofNumber must be zero"
        );
    }
}
