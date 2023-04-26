pragma solidity ^0.5.0;

import "@openzeppelin/contracts/token/ERC721/ERC721Full.sol";
import "./IGeneScience.sol";
import "./GFAccessControl.sol";
import "./ISaleClockAuction.sol";

/// @title Base contract for GameAlianas. Holds all common structs, events and base variables.
/// @dev See the AlianaCore contract documentation to understand how the various contract facets are arranged.
contract AlianaBase is GFAccessControl, ERC721Full {
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public whenNotPaused {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public whenNotPaused {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public whenNotPaused {
        super.safeTransferFrom(from, to, tokenId, _data);
    }

    /// @dev The address of the sibling contract that is used to implement the sooper-sekret
    ///  genetic combination algorithm.
    IGeneScience internal geneScience;

    /// @dev Update the address of the genetic contract, can only be called by the CEO.
    /// @param _address An address of a GeneScience contract instance to be used from this point forward.
    function setGeneScienceAddress(IGeneScience _address) public onlyCEO {
        require(_address.isGeneScience(), "Aliana: not gene");

        // Set the new contract address
        geneScience = _address;
    }

    function getGeneScienceAddress()
        external
        view
        onlyCLevelOrWhitelisted
        returns (address)
    {
        return address(geneScience);
    }

    function isAliana() external pure returns (bool) {
        return true;
    }

    // Initializing an ERC-721 Token named 'Vipers' with a symbol 'VPR'
    constructor() public ERC721Full("Game Fantasy Alianas", "GFA") {}

    /*** DATA TYPES ***/

    /// @dev The main Aliana struct. Every cat in GameAlianas is represented by a copy
    ///  of this structure, so great care was taken to ensure that it fits neatly into
    ///  exactly two 256-bit words. Note that the order of the members in this structure
    ///  is important because of the byte-packing rules used by Ethereum.
    ///  Ref: http://solidity.readthedocs.io/en/develop/miscellaneous.html
    struct Aliana {
        // The Aliana's genetic code is packed into these 256-bits, the format is
        // sooper-sekret! A cat's genes never change.
        uint256 genes;
        // The timestamp from the block when this cat came into existence.
        uint64 birthTime;
        // The ID of the parents of this aliana, set to 0 for gen0 cats.
        // Note that using 32-bit unsigned integers limits us to a "mere"
        // 4 billion cats. This number might seem small until you realize
        // that Ethereum currently has a limit of about 500 million
        // transactions per year! So, this definitely won't be a problem
        // for several years (even as Ethereum learns to scale).
        uint64 matronId;
        uint64 sireId;
    }

    /*** STORAGE ***/

    /// @dev An array containing the Aliana struct for all Kitties in existence. The ID
    ///  of each cat is actually an index into this array.
    Aliana[] public alianas;

    /// @dev An internal method that creates a new aliana and stores it. This
    ///  method doesn't do any checking and should only be called when the
    ///  input data is known to be valid. Will generate both a Birth event
    ///  and a Transfer event.
    /// @param _matronId The aliana ID of the matron of this cat (zero for gen0)
    /// @param _sireId The aliana ID of the sire of this cat (zero for gen0)
    /// @param _genes The aliana's genetic code.
    /// @param _owner The inital owner of this cat, must be non-zero (except for the unAliana, ID 0)
    function _createAliana(
        uint256 _matronId,
        uint256 _sireId,
        uint256 _genes,
        address _owner
    ) internal returns (uint256) {
        require(
            geneScience.isValid(int256(alianas.length), _genes),
            "Aliana: genes isn't valid"
        );
        Aliana memory _aliana = Aliana({
            genes: _genes,
            birthTime: uint64(now),
            matronId: uint64(_matronId),
            sireId: uint64(_sireId)
        });
        uint256 newKittenId = alianas.push(_aliana) - 1;

        // This will assign ownership, and also emit the Transfer event as
        // per ERC721 draft
        super._mint(_owner, newKittenId);
        return newKittenId;
    }

    /// @notice Returns all the relevant information about a specific aliana.
    /// @param _id The ID of the aliana of interest.
    function getAliana(uint256 _id)
        external
        view
        returns (
            uint256 birthTime,
            uint256 matronId,
            uint256 sireId,
            uint256 genes,
            uint256 lpLabor
        )
    {
        Aliana storage kit = alianas[_id];

        birthTime = uint256(kit.birthTime);
        matronId = uint256(kit.matronId);
        sireId = uint256(kit.sireId);
        genes = kit.genes;
        lpLabor = uint64(geneScience.geneLpLabor(int256(_id), kit.genes));
    }
}
