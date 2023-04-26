pragma solidity 0.5.17;

import "./DloopGovernance.sol";
import "./DloopUtil.sol";

contract DloopArtwork is DloopGovernance, DloopUtil {
    uint16 private constant MAX_EDITION_SIZE = 10000;
    uint16 private constant MIN_EDITION_SIZE = 1;

    uint8 private constant MAX_ARTIST_PROOF_SIZE = 10;
    uint8 private constant MIN_ARTIST_PROOF_SIZE = 1;

    struct Artwork {
        uint16 editionSize;
        uint16 editionCounter;
        uint8 artistProofSize;
        uint8 artistProofCounter;
        bool hasEntry;
        Data[] dataArray;
    }

    mapping(uint64 => Artwork) private _artworkMap; //uint64 represents the artworkId

    event ArtworkCreated(uint64 indexed artworkId);
    event ArtworkDataAdded(uint64 indexed artworkId, bytes32 indexed dataType);

    function createArtwork(
        uint64 artworkId,
        uint16 editionSize,
        uint8 artistProofSize,
        bytes32 dataType,
        bytes memory data
    ) public onlyMinter returns (bool) {
        require(!_artworkMap[artworkId].hasEntry, "artworkId already exists");
        require(editionSize <= MAX_EDITION_SIZE, "editionSize exceeded");
        require(
            editionSize >= MIN_EDITION_SIZE,
            "editionSize must be positive"
        );
        require(
            artistProofSize <= MAX_ARTIST_PROOF_SIZE,
            "artistProofSize exceeded"
        );
        require(
            artistProofSize >= MIN_ARTIST_PROOF_SIZE,
            "artistProofSize must be positive"
        );

        _artworkMap[artworkId].hasEntry = true;
        _artworkMap[artworkId].editionSize = editionSize;
        _artworkMap[artworkId].artistProofSize = artistProofSize;

        emit ArtworkCreated(artworkId);
        addArtworkData(artworkId, dataType, data);

        return true;
    }

    function _updateArtwork(
        uint64 artworkId,
        uint16 editionNumber,
        uint8 artistProofNumber
    ) internal {
        Artwork storage aw = _artworkMap[artworkId];

        require(aw.hasEntry, "artworkId does not exist");

        if (editionNumber > 0) {
            require(
                editionNumber <= aw.editionSize,
                "editionNumber must not exceed editionSize"
            );
            aw.editionCounter = aw.editionCounter + 1;
        }

        if (artistProofNumber > 0) {
            require(
                artistProofNumber <= aw.artistProofSize,
                "artistProofNumber must not exceed artistProofSize"
            );
            aw.artistProofCounter = aw.artistProofCounter + 1;
        }
    }

    function addArtworkData(
        uint64 artworkId,
        bytes32 dataType,
        bytes memory data
    ) public onlyMinter returns (bool) {
        require(_artworkMap[artworkId].hasEntry, "artworkId does not exist");
        require(artworkId > 0, "artworkId must be greater than 0");
        require(dataType != 0x0, "dataType must not be 0x0");
        require(data.length >= MIN_DATA_LENGTH, "data required");
        require(data.length <= MAX_DATA_LENGTH, "data exceeds maximum length");

        _artworkMap[artworkId].dataArray.push(Data(dataType, data));

        emit ArtworkDataAdded(artworkId, dataType);
        return true;
    }

    function getArtworkDataLength(uint64 artworkId)
        public
        view
        returns (uint256)
    {
        require(_artworkMap[artworkId].hasEntry, "artworkId does not exist");
        return _artworkMap[artworkId].dataArray.length;
    }

    function getArtworkData(uint64 artworkId, uint256 index)
        public
        view
        returns (bytes32 dataType, bytes memory data)
    {
        Artwork memory aw = _artworkMap[artworkId];

        require(aw.hasEntry, "artworkId does not exist");
        require(
            index < aw.dataArray.length,
            "artwork data index is out of bounds"
        );

        dataType = aw.dataArray[index].dataType;
        data = aw.dataArray[index].data;
    }

    function getArtworkInfo(uint64 artworkId)
        public
        view
        returns (
            uint16 editionSize,
            uint16 editionCounter,
            uint8 artistProofSize,
            uint8 artistProofCounter
        )
    {
        Artwork memory aw = _artworkMap[artworkId];
        require(aw.hasEntry, "artworkId does not exist");

        editionSize = aw.editionSize;
        editionCounter = aw.editionCounter;
        artistProofSize = aw.artistProofSize;
        artistProofCounter = aw.artistProofCounter;
    }
}
