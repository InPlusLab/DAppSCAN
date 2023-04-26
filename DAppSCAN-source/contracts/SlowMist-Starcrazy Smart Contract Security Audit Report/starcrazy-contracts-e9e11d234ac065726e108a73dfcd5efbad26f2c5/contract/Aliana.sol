pragma solidity ^0.5.0;

import "./aliana/AlianaOwnership.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./aliana/IGeneScience.sol";

/// @title A facet of AlianaCore that manages Aliana siring, gestation, and birth.
/// @dev See the AlianaCore contract documentation to understand how the various contract facets are arranged.
contract Aliana is AlianaOwnership {
    constructor(IGeneScience _geneAddr) public {
        require(_geneAddr.isGeneScience(), "Aliana: isGeneScience false");
        setGeneScienceAddress(_geneAddr);
        require(
            _createAliana(0, 0, 0, address(this)) == 0,
            "Aliana: card #0 must be my own"
        );
    }

    /// @notice Have a pregnant Aliana give birth!
    /// @param _matronId A Aliana ready to give birth.
    /// @return The Aliana ID of the new kitten.
    /// @dev Looks at a given Aliana and, if pregnant and if the gestation period has passed,
    ///  combines the genes of the two parents to create a new kitten. The new Aliana is assigned
    ///  to the current owner of the matron. Upon successful completion, both the matron and the
    ///  new kitten will be ready to breed again. Note that anyone can call this function (if they
    ///  are willing to pay the gas!), but the new kitten always goes to the mother's owner.
    function mix(uint256 _matronId, uint256 _sireId)
        external
        whenNotPaused
        returns (uint256)
    {
        require(
            _matronId != _sireId,
            "Aliana: only different aliana can be merged"
        );
        require(ownerOf(_matronId) == msg.sender, "Aliana: must be the owner");
        require(ownerOf(_sireId) == msg.sender, "Aliana: must be the owner");

        // Grab a reference to the matron in storage.
        Aliana storage matron = alianas[_matronId];

        Aliana storage sire = alianas[_sireId];

        // Check that the matron is a valid cat.
        require(matron.birthTime != 0, "Aliana: matron birthTime not valid");

        // Check that the matron is a valid cat.
        require(sire.birthTime != 0, "Aliana: sire birthTime not valid");

        uint256 totalCats = totalAlianaSupply();
        // Call the sooper-sekret gene mixing operation.
        uint256 childGenes = geneScience.mixGenes(
            int256(_matronId),
            int256(_sireId),
            matron.genes,
            sire.genes,
            totalCats
        );

        _burn(msg.sender, _matronId);
        _burn(msg.sender, _sireId);

        // Make the new kitten!
        uint256 kittenId = _createAliana(
            _matronId,
            _sireId,
            childGenes,
            msg.sender
        );

        emit Mix(msg.sender, _matronId, _sireId, kittenId);

        // return the new kitten's ID
        return kittenId;
    }

    function burn(uint256 _tokenID) external {
        require(ownerOf(_tokenID) == msg.sender, "Aliana: must be the owner");
        _burn(msg.sender, _tokenID);
    }

    function geneLpLabor(int256 _id, uint256 _gene)
        public
        view
        returns (uint256)
    {
        return geneScience.geneLpLabor(_id, _gene);
    }

    function geneLpLabors(int256[] calldata _ids, uint256[] calldata _genes)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory res = new uint256[](_genes.length);
        for (uint256 i = 0; i < _genes.length; i++) {
            res[i] = geneScience.geneLpLabor(_ids[i], _genes[i]);
        }
        return res;
    }

    /// @dev we can create Official alianas, up to a limit. Only callable by Official contract
    /// @param _genes the encoded genes of the kitten to be created, any value is accepted
    /// @param _owner the future owner of the created alianas. Default to contract COO
    function createOfficialAliana(uint256 _genes, address _owner)
        external
        onlyWhitelisted
        returns (uint256)
    {
        return _createAliana(0, 0, _genes, _owner);
    }

    /// @dev we can create Official alianas, up to a limit. Only callable by Official contract
    /// @param _genes the encoded genes of the kitten to be created, any value is accepted
    /// @param _owner the future owner of the created alianas. Default to contract COO
    function createOfficialAliana(
        uint256 _matronId,
        uint256 _sireId,
        uint256 _genes,
        address _owner
    ) external onlyWhitelisted returns (uint256) {
        return _createAliana(_matronId, _sireId, _genes, _owner);
    }

    /// @dev we can create promo alianas, up to a limit. Only callable by COO
    /// @param _genes the encoded genes of the kitten to be created, any value is accepted
    /// @param _owner the future owner of the created alianas. Default to contract COO
    function createPromoAliana(uint256 _genes, address _owner)
        external
        onlyCLevel
        returns (uint256)
    {
        address alianaOwner = _owner;
        if (alianaOwner == address(0)) {
            alianaOwner = msg.sender;
        }

        return _createAliana(0, 0, _genes, alianaOwner);
    }

    event Mix(
        address indexed src,
        uint256 indexed matronId,
        uint256 indexed sireId,
        uint256 kittenId
    );
}
