pragma solidity 0.5.17;

import "./DloopWithdraw.sol";
import "./DloopArtwork.sol";

contract DloopMintable is DloopWithdraw, DloopArtwork {
    mapping(uint256 => Data[]) private _dataMap; //uint256 represents the tokenId

    event EditionMinted(
        uint256 indexed tokenId,
        uint64 indexed artworkId,
        uint16 editionNumber,
        uint8 artistProofNumber
    );
    event EditionDataAdded(uint256 indexed tokenId, bytes32 indexed dataType);

    function mintEdition(
        address to,
        uint64 artworkId,
        uint16 editionNumber,
        uint8 artistProofNumber,
        bytes32 dataType,
        bytes memory data
    ) public onlyMinter returns (bool) {
        uint256 tokenId = super.createTokenId(
            artworkId,
            editionNumber,
            artistProofNumber
        );

        super._safeMint(to, tokenId);
        super._setManaged(tokenId, true);

        super._updateArtwork(artworkId, editionNumber, artistProofNumber);

        emit EditionMinted(
            tokenId,
            artworkId,
            editionNumber,
            artistProofNumber
        );

        // Special case. If dataType is set, add the data
        if (dataType != 0x0) {
            addEditionData(tokenId, dataType, data);
        }

        return true;
    }

    function addEditionData(
        uint256 tokenId,
        bytes32 dataType,
        bytes memory data
    ) public onlyMinter returns (bool) {
        require(super._exists(tokenId), "tokenId does not exist");
        require(dataType != 0x0, "dataType must not be 0x0");
        require(data.length >= MIN_DATA_LENGTH, "data required");
        require(data.length <= MAX_DATA_LENGTH, "data exceeds maximum length");

        _dataMap[tokenId].push(Data(dataType, data));

        emit EditionDataAdded(tokenId, dataType);
        return true;
    }

    function getEditionDataLength(uint256 tokenId)
        public
        view
        returns (uint256)
    {
        require(_exists(tokenId), "tokenId does not exist");
        return _dataMap[tokenId].length;
    }

    function getEditionData(uint256 tokenId, uint256 index)
        public
        view
        returns (bytes32 dataType, bytes memory data)
    {
        require(_exists(tokenId), "tokenId does not exist");
        require(
            index < _dataMap[tokenId].length,
            "edition data index is out of bounds"
        );

        dataType = _dataMap[tokenId][index].dataType;
        data = _dataMap[tokenId][index].data;
    }
}
