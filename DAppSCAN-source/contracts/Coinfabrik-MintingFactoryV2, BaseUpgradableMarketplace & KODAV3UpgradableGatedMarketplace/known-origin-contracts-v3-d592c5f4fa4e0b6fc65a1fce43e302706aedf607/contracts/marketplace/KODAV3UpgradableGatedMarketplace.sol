// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {BaseUpgradableMarketplace} from "./BaseUpgradableMarketplace.sol";
import {IKODAV3} from "../core/IKODAV3.sol";
import {IKOAccessControlsLookup} from "../access/IKOAccessControlsLookup.sol";
import {IKODAV3GatedMarketplace} from "./IKODAV3Marketplace.sol";

contract KODAV3UpgradableGatedMarketplace is IKODAV3GatedMarketplace, BaseUpgradableMarketplace {

    /// @notice emitted when admin updates funds receiver
    event AdminUpdateFundReceiver(uint256 indexed _saleId, address _newFundsReceiver);

    /// @notice emitted when admin updates max edition ID
    event AdminUpdateMaxEditionId(uint256 indexed _saleId, uint256 _newMaxEditionId);

    /// @notice emitted when admin updates creator
    event AdminUpdateCreator(uint256 indexed _saleId, address _newCreator);

    /// @notice emitted when gated sale commission is updated for a given sale
    event AdminSetKoCommissionOverrideForSale(uint256 indexed _saleId, uint256 _platformPrimarySaleCommission);

    /// @notice emitted when a sale is paused
    event SalePaused(uint256 indexed _saleId);

    /// @notice emitted when a sale is resumed
    event SaleResumed(uint256 indexed _saleId);

    /// @notice emitted when a sale and its phases are created
    event SaleWithPhaseCreated(uint256 indexed _saleId);

    /// @notice emitted when a sale without any phases created
    event SaleCreated(uint256 indexed _saleId);

    /// @notice emitted when a new phase is added to a sale
    event PhaseCreated(uint256 indexed _saleId, uint256 indexed _phaseId);

    /// @notice emitted when a phase is removed from a sale
    event PhaseRemoved(uint256 indexed _saleId, uint256 indexed _phaseId);

    /// @notice emitted when someone mints from a sale
    event MintFromSale(uint256 indexed _saleId, uint256 indexed _phaseId, uint256 indexed _tokenId, address _recipient);

    /// @notice Phase represents a time structured part of a sale, i.e. VIP, pre sale or open sale
    struct Phase {
        uint128 startTime;      // The start time of the sale as a whole
        uint128 endTime;        // The end time of the sale phase, also the beginning of the next phase if applicable
        uint128 priceInWei;     // Price in wei for one mint
        uint16 mintCounter;     // The current amount of items minted
        uint16 mintCap;         // The maximum amount of mints for the phase
        uint16 walletMintLimit; // The mint limit per wallet for the phase
        bytes32 merkleRoot;     // The merkle tree root for the phase
        string merkleIPFSHash;  // The IPFS hash referencing the merkle tree
    }

    /// @notice Sale represents a gated sale, with mapping links to different sale phases
    struct Sale {
        uint256 id;             // The ID of the sale
        uint256 editionId;      // The ID of the edition the sale will mint
        address creator;        // Set on creation to save gas - the original edition creator
        address fundsReceiver;  // Where are the funds set
        uint256 maxEditionId;   // Stores the max edition ID for the edition - used when assigning tokens
        uint16 mintCounter;     // Keeps a pointer to the overall mint count for the full sale
        uint8 paused;           // Whether the sale is currently paused > 0 is paused
    }

    /// @notice sale Id -> KO commission override
    mapping(uint256 => KOCommissionOverride) public koCommissionOverrideForSale;

    /// @dev incremental counter for the ID of a sale
    uint256 public saleIdCounter;

    /// @dev totalMints is a mapping of hash(sale id, phase id, address) => total minted by that address
    mapping(bytes32 => uint256) public totalMints;

    /// @dev edition to sale is a mapping of edition id => sale id
    mapping(uint256 => uint256) public editionToSale;

    /// @dev sales is a mapping of sale id => Sale
    mapping(uint256 => Sale) public sales;

    /// @dev phases is a mapping of sale id => array of associated phases
    mapping(uint256 => Phase[]) public phases;

    /// @notice Allow an artist or admin to create a sale with 1 or more phases
    function createSaleWithPhases(
        uint256 _editionId,
        uint128[] memory _startTimes,
        uint128[] memory _endTimes,
        uint128[] memory _pricesInWei,
        uint16[] memory _mintCaps,
        uint16[] memory _walletMintLimits,
        bytes32[] memory _merkleRoots,
        string[] memory _merkleIPFSHashes
    ) external override whenNotPaused {
        address creator = koda.getCreatorOfEdition(_editionId);
        require(
            creator == _msgSender() || accessControls.hasContractOrAdminRole(_msgSender()),
            "Caller not creator or admin"
        );

        // Check no existing sale in place
        require(editionToSale[_editionId] == 0, "Sale exists for this edition");

        uint256 saleId = _createSale(_editionId, creator);

        _addMultiplePhasesToSale(
            saleId,
            _startTimes,
            _endTimes,
            _pricesInWei,
            _mintCaps,
            _walletMintLimits,
            _merkleRoots,
            _merkleIPFSHashes
        );

        emit SaleWithPhaseCreated(saleId);
    }

    /// @notice Allow an artist or admin to create a sale with 0 phases
    function createSale(uint256 _editionId) external override whenNotPaused {
        address creator = koda.getCreatorOfEdition(_editionId);
        require(
            creator == _msgSender() || accessControls.hasContractOrAdminRole(_msgSender()),
            "Caller not creator or admin"
        );

        // Check no existing sale in place
        require(editionToSale[_editionId] == 0, "Sale exists for this edition");

        uint256 saleId = _createSale(_editionId, creator);

        emit SaleCreated(saleId);
    }

    function _createSale(uint256 _editionId, address _creator) internal returns (uint256) {
        uint256 saleId = ++saleIdCounter;

        // Assign the sale to the sales and editionToSale mappings
        sales[saleId] = Sale({
        id : saleId,
        creator : _creator,
        fundsReceiver : koda.getRoyaltiesReceiver(_editionId),
        editionId : _editionId,
        maxEditionId : koda.maxTokenIdOfEdition(_editionId) - 1,
        paused : 0,
        mintCounter : 0
        });

        editionToSale[_editionId] = saleId;

        return saleId;
    }

    /// @notice Mint an NFT from the gated list
    function mint(
        uint256 _saleId,
        uint256 _phaseId,
        uint16 _mintCount,
        uint256 _index,
        bytes32[] calldata _merkleProof
    ) payable external nonReentrant whenNotPaused {
        Sale storage sale = sales[_saleId];
        require(sale.paused == 0, 'Sale is paused');

        Phase storage phase = phases[_saleId][_phaseId];

        require(block.timestamp >= phase.startTime && block.timestamp < phase.endTime, 'Sale phase not in progress');
        require(phase.mintCounter + _mintCount <= phase.mintCap, 'Phase mint cap reached');

        bytes32 totalMintsKey = keccak256(abi.encode(_saleId, _phaseId, _msgSender()));

        require(totalMints[totalMintsKey] + _mintCount <= phase.walletMintLimit, 'Cannot exceed total mints for sale phase');
        require(msg.value >= phase.priceInWei * _mintCount, 'Not enough wei sent to complete mint');
        require(onPhaseMintList(_saleId, _phaseId, _index, _msgSender(), _merkleProof), 'Address not able to mint from sale');

        handleMint(_saleId, _phaseId, sale.editionId, _mintCount, _msgSender());

        // Up the mint count for the user and the phase mint counter
        totalMints[totalMintsKey] += _mintCount;
        phase.mintCounter += _mintCount;
        sale.mintCounter += _mintCount;
    }

    function createPhase(
        uint256 _editionId,
        uint128 _startTime,
        uint128 _endTime,
        uint128 _priceInWei,
        uint16 _mintCap,
        uint16 _walletMintLimit,
        bytes32 _merkleRoot,
        string calldata _merkleIPFSHash
    )
    external override whenNotPaused onlyCreatorContractOrAdmin(_editionId) {
        uint256 saleId = editionToSale[_editionId];
        require(saleId > 0, 'No sale associated with edition id');

        _addPhaseToSale(
            saleId,
            _startTime,
            _endTime,
            _priceInWei,
            _mintCap,
            _walletMintLimit,
            _merkleRoot,
            _merkleIPFSHash
        );
    }

    function createPhases(
        uint256 _editionId,
        uint128[] memory _startTimes,
        uint128[] memory _endTimes,
        uint128[] memory _pricesInWei,
        uint16[] memory _mintCaps,
        uint16[] memory _walletMintLimits,
        bytes32[] memory _merkleRoots,
        string[] memory _merkleIPFSHashes
    )
    external override onlyCreatorContractOrAdmin(_editionId) whenNotPaused {

        // Ensure sale is valid
        uint256 saleId = editionToSale[_editionId];
        require(saleId > 0, 'No sale associated with edition id');

        _addMultiplePhasesToSale(
            saleId,
            _startTimes,
            _endTimes,
            _pricesInWei,
            _mintCaps,
            _walletMintLimits,
            _merkleRoots,
            _merkleIPFSHashes
        );
    }

    function removePhase(uint256 _editionId, uint256 _phaseId)
    external override onlyCreatorContractOrAdmin(_editionId) {
        require(koda.editionExists(_editionId), 'Edition does not exist');

        uint256 saleId = editionToSale[_editionId];
        require(saleId > 0, 'No sale associated with edition id');

        delete phases[saleId][_phaseId];

        emit PhaseRemoved(saleId, _phaseId);
    }

    /// @dev checks whether a given user is on the list to mint from a phase
    function onPhaseMintList(uint256 _saleId, uint256 _phaseId, uint256 _index, address _account, bytes32[] calldata _merkleProof)
    public view returns (bool) {
        Phase storage phase = phases[_saleId][_phaseId];
        // assume balance of 1 for enabled with access to the sale
        bytes32 node = keccak256(abi.encodePacked(_index, _account, uint256(1)));
        return MerkleProof.verify(_merkleProof, phase.merkleRoot, node);
    }

    function toggleSalePause(uint256 _saleId, uint256 _editionId) external onlyCreatorContractOrAdmin(_editionId) {
        if (sales[_saleId].paused != 0) {
            sales[_saleId].paused = 0;
            emit SaleResumed(_saleId);
        } else {
            sales[_saleId].paused = 1;
            emit SalePaused(_saleId);
        }
    }

    function remainingPhaseMintAllowance(uint256 _saleId, uint256 _phaseId, uint256 _index, address _account, bytes32[] calldata _merkleProof)
    external view returns (uint256) {
        require(onPhaseMintList(_saleId, _phaseId, _index, _account, _merkleProof), 'Address not able to mint from sale');

        return phases[_saleId][_phaseId].walletMintLimit - totalMints[keccak256(abi.encode(_saleId, _phaseId, _account))];
    }

    function handleMint(
        uint256 _saleId,
        uint256 _phaseId,
        uint256 _editionId,
        uint16 _mintCount,
        address _recipient
    ) internal {
        require(_mintCount > 0, "Nothing being minted");

        address creator = sales[_saleId].creator;
        uint256 startId = sales[_saleId].maxEditionId - sales[_saleId].mintCounter;

        for (uint256 i; i < _mintCount; ++i) {
            uint256 tokenId = getNextAvailablePrimarySaleToken(startId, _editionId, creator);

            // send token to buyer (assumes approval has been made, if not then this will fail)
            koda.safeTransferFrom(creator, _recipient, tokenId);

            emit MintFromSale(_saleId, _phaseId, tokenId, _recipient);

            // reduce start ID to allow to optimised token ID determination
            unchecked {startId = tokenId--;}
        }
        _handleSaleFunds(sales[_saleId].fundsReceiver, getPlatformSaleCommissionForSale(_saleId));
    }

    function getPlatformSaleCommissionForSale(uint256 _saleId) internal view returns (uint256) {
        if (koCommissionOverrideForSale[_saleId].active) {
            return koCommissionOverrideForSale[_saleId].koCommission;
        }
        return platformPrimaryCommission;
    }

    function getNextAvailablePrimarySaleToken(uint256 _startId, uint256 _editionId, address creator) internal view returns (uint256 _tokenId) {
        for (uint256 tokenId = _startId; tokenId >= _editionId; --tokenId) {
            if (koda.ownerOf(tokenId) == creator) {
                return tokenId;
            }
        }
        revert("Primary market exhausted");
    }

    function _addMultiplePhasesToSale(
        uint256 _saleId,
        uint128[] memory _startTimes,
        uint128[] memory _endTimes,
        uint128[] memory _pricesInWei,
        uint16[] memory _mintCaps,
        uint16[] memory _walletMintLimits,
        bytes32[] memory _merkleRoots,
        string[] memory _merkleIPFSHashes
    ) internal {
        uint256 numOfPhases = _startTimes.length;
        for (uint256 i; i < numOfPhases; ++i) {
            _addPhaseToSale(
                _saleId,
                _startTimes[i],
                _endTimes[i],
                _pricesInWei[i],
                _mintCaps[i],
                _walletMintLimits[i],
                _merkleRoots[i],
                _merkleIPFSHashes[i]
            );
        }
    }

    function _addPhaseToSale(
        uint256 _saleId,
        uint128 _startTime,
        uint128 _endTime,
        uint128 _priceInWei,
        uint16 _mintCap,
        uint16 _walletMintLimit,
        bytes32 _merkleRoot,
        string memory _merkleIPFSHash
    ) internal {
        require(_endTime > _startTime, 'Phase end time must be after start time');
        require(_walletMintLimit > 0, 'Zero mint limit');
        require(_mintCap > 0, "Zero mint cap");
        require(_merkleRoot != bytes32(0), "Zero merkle root");
        require(bytes(_merkleIPFSHash).length == 46, "Invalid IPFS hash");

        // Add the phase to the phases mapping
        phases[_saleId].push(Phase({
            startTime : _startTime,
            endTime : _endTime,
            priceInWei : _priceInWei,
            mintCounter : 0,
            mintCap : _mintCap,
            walletMintLimit : _walletMintLimit,
            merkleRoot : _merkleRoot,
            merkleIPFSHash : _merkleIPFSHash
        }));

        emit PhaseCreated(_saleId, phases[_saleId].length - 1);
    }

    function updateFundsReceiver(uint256 _saleId, address _newFundsReceiver) public onlyAdmin {
        require(_newFundsReceiver != address(0), "Unable to send funds to invalid address");
        sales[_saleId].fundsReceiver = _newFundsReceiver;
        emit AdminUpdateFundReceiver(_saleId, _newFundsReceiver);
    }

    function updateMaxEditionId(uint256 _saleId, uint256 _newMaxEditionId) public onlyAdmin {
        require(_newMaxEditionId >= 1, "Unable to set max edition");
        sales[_saleId].maxEditionId = _newMaxEditionId;
        emit AdminUpdateMaxEditionId(_saleId, _newMaxEditionId);
    }

    function updateCreator(uint256 _saleId, address _newCreator) public onlyAdmin {
        require(_newCreator != address(0), "Unable to make invalid address creator");
        sales[_saleId].creator = _newCreator;
        emit AdminUpdateCreator(_saleId, _newCreator);
    }

    function setKoCommissionOverrideForSale(uint256 _saleId, bool _active, uint256 _koCommission) public onlyAdmin {
        KOCommissionOverride storage koCommissionOverride = koCommissionOverrideForSale[_saleId];
        koCommissionOverride.active = _active;
        koCommissionOverride.koCommission = _koCommission;
        emit AdminSetKoCommissionOverrideForSale(_saleId, _koCommission);
    }
}
