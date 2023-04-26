// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {IKODAV3GatedMerkleMarketplace} from "./IKODAV3GatedMerkleMarketplace.sol";
import {BaseUpgradableMarketplace} from "../../marketplace/BaseUpgradableMarketplace.sol";
import {IKOAccessControlsLookup} from "../../access/IKOAccessControlsLookup.sol";
import {IKODAV3} from "../../core/IKODAV3.sol";

/// @title Merkle based gated pre-list marketplace
contract KODAV3GatedMerkleMarketplace is BaseUpgradableMarketplace, IKODAV3GatedMerkleMarketplace {

    /// @notice emitted when a sale, with a single phase, is created
    event MerkleSaleWithPhaseCreated(uint256 indexed saleId);

    /// @notice emitted when a new phase is added to a sale
    event MerklePhaseCreated(uint256 indexed saleId, bytes32 indexed phaseId);

    /// @notice emitted when a phase is removed from a sale
    event MerklePhaseRemoved(uint256 indexed saleId, bytes32 indexed phaseId);

    /// @notice emitted when a sale is paused
    event MerkleSalePauseUpdated(uint256 indexed saleId, bool isPaused);

    /// @notice emitted when someone mints from a sale
    event MerkleMintFromSale(uint256 indexed saleId, uint256 indexed phaseId, uint256 indexed tokenId, address account);

    modifier onlyCreatorOrAdminForSale(uint256 _saleId) {
        require(
            koda.getCreatorOfEdition(editionToSale[_saleId]) == _msgSender() || accessControls.hasAdminRole(_msgSender()),
            "Caller not creator or admin of sale"
        );
        _;
    }

    /// @dev incremental counter for the ID of a sale
    uint256 public saleIdCounter;

    /// @notice Whether a sale is paused
    mapping(uint256 => bool) public isMerkleSalePaused;

    /// @notice Whether a phase is whitelisted within a sale
    mapping(uint256 => mapping(bytes32 => bool)) public isPhaseWhitelisted; //sale id => phase id => is whitelisted

    /// @notice Track the current amount of items minted to make sure it doesn't exceed a cap
    mapping(bytes32 => uint16) public phaseMintCount;

    /// @notice Keeps a pointer to the overall mint count for the full sale
    mapping(uint256 => uint16) public saleMintCount;

    /// @dev edition to sale is a mapping of edition id => sale id
    mapping(uint256 => uint256) public editionToSale;

    /// @dev totalMints is a mapping of hash(sale id, phase id, address) => total minted by that address
    mapping(bytes32 => uint256) public totalMints;

    /// @notice sale Id -> KO commission override
    mapping(uint256 => KOCommissionOverride) public koCommissionOverrideForSale;

    /// @inheritdoc IKODAV3GatedMerkleMarketplace
    function createMerkleSaleWithPhases(uint256 _editionId, bytes32[] calldata _phaseIds)
    external
    override
    whenNotPaused
    onlyCreatorContractOrAdmin(_editionId) {
        uint256 editionSize = koda.getSizeOfEdition(_editionId);
        require(editionSize > 0, 'edition does not exist');

        uint256 saleId;
        unchecked {
            saleId = ++saleIdCounter;
        }

        // Assign the sale to the edition
        editionToSale[saleId] = _editionId;

        // whitelist the phases
        _addPhasesToSale(saleId, _phaseIds);

        emit MerkleSaleWithPhaseCreated(saleId);
    }

    /// @inheritdoc IKODAV3GatedMerkleMarketplace
    function merkleMint(
        uint256 _saleId,
        bytes32 _phaseId,
        uint16 _mintCount,
        address _recipient,
        MerklePhaseMetadata calldata _phase,
        bytes32[] calldata _merkleProof
    ) payable external override nonReentrant whenNotPaused {
        uint256 editionId = editionToSale[_saleId];
        require(editionId > 0, "no sale exists");
        require(!isMerkleSalePaused[_saleId], 'sale is paused');

        require(block.timestamp >= _phase.startTime && block.timestamp < _phase.endTime, 'sale phase not in progress');
        require(phaseMintCount[_phaseId] + _mintCount <= _phase.mintCap, 'phase mint cap reached');

        bytes32 totalMintsKey = keccak256(abi.encode(_saleId, _phaseId, _msgSender()));

        require(totalMints[totalMintsKey] + _mintCount <= _phase.walletMintLimit, 'cannot exceed total mints for sale phase');
        require(msg.value == _phase.priceInWei * _mintCount, 'not enough wei sent to complete mint');
        require(onPhaseMerkleList(_saleId, _phaseId, _msgSender(), _phase, _merkleProof), 'address not able to mint from sale');

        handleMerkleMint(_saleId, uint256(_phaseId), editionId, _phase.maxEditionId, _mintCount, _recipient, _phase.creator, _phase.fundsReceiver);

        // Up the mint count for the user and the phase mint counter
        totalMints[totalMintsKey] += _mintCount;
        phaseMintCount[_phaseId] += _mintCount;
        saleMintCount[_saleId] += _mintCount;
    }

    /// @inheritdoc IKODAV3GatedMerkleMarketplace
    function addPhasesToMerkleSale(uint256 _saleId, bytes32[] calldata _phaseIds)
    external
    override
    whenNotPaused
    onlyCreatorOrAdminForSale(_saleId) {
        // Add the phase to the phases mapping
        _addPhasesToSale(_saleId, _phaseIds);
    }

    /// @inheritdoc IKODAV3GatedMerkleMarketplace
    function removePhasesFromMerkleSale(uint256 _saleId, bytes32[] calldata _phaseIds)
    external
    override
    onlyCreatorOrAdminForSale(_saleId)
    {
        require(editionToSale[_saleId] > 0, 'no sale associated with edition id');
        unchecked {
            uint256 numPhaseIds = _phaseIds.length;
            for (uint256 i; i < numPhaseIds; ++i) {
                bytes32 _phaseId = _phaseIds[i];
                isPhaseWhitelisted[_saleId][_phaseId] = false;
                emit MerklePhaseRemoved(_saleId, _phaseId);
            }
        }
    }

    /// @inheritdoc IKODAV3GatedMerkleMarketplace
    function onPhaseMerkleList(
        uint256 _saleId,
        bytes32 _phaseId,
        address _account,
        MerklePhaseMetadata calldata _phase,
        bytes32[] calldata _merkleProof
    ) public override view returns (bool) {
        require(_phase.endTime > _phase.startTime, 'phase end time must be after start time');
        require(isPhaseWhitelisted[_saleId][_phaseId], 'phase id does not exist');

        bytes32 node = keccak256(abi.encodePacked(
                _phase.startTime,
                _phase.endTime,
                _phase.walletMintLimit,
                _phase.priceInWei,
                _phase.mintCap,
                _account,
                address(this) //ensure merkle proof for this contract only
            ));

        return MerkleProof.verify(_merkleProof, _phaseId, node);
    }

    /// @inheritdoc IKODAV3GatedMerkleMarketplace
    function remainingMerklePhaseMintAllowance(
        uint256 _saleId,
        bytes32 _phaseId,
        address _account,
        MerklePhaseMetadata calldata _phase,
        bytes32[] calldata _merkleProof
    ) external override view returns (uint256) {
        require(onPhaseMerkleList(_saleId, _phaseId, _account, _phase, _merkleProof), 'address not able to mint from sale');
        return _phase.walletMintLimit - totalMints[keccak256(abi.encode(_saleId, _phaseId, _account))];
    }

    /// @notice Enable or disable all phases within a sale for an edition
    function toggleMerkleSalePause(uint256 _saleId) external override onlyCreatorOrAdminForSale(_saleId) {
        isMerkleSalePaused[_saleId] = !isMerkleSalePaused[_saleId];
        emit MerkleSalePauseUpdated(_saleId, isMerkleSalePaused[_saleId]);
    }

    /// @dev Enable a list of phases within a sale for an edition
    function _addPhasesToSale(uint256 _saleId, bytes32[] calldata _phaseIds) internal {
        unchecked {
            uint256 numberOfPhases = _phaseIds.length;
            require(numberOfPhases > 0, "No phases");

            uint256 editionId = editionToSale[_saleId];
            require(editionId > 0, 'invalid sale');

            for (uint256 i; i < numberOfPhases; ++i) {
                bytes32 _phaseId = _phaseIds[i];

                require(_phaseId != bytes32(0), "Invalid ID");
                require(!isPhaseWhitelisted[_saleId][_phaseId], "Already enabled");

                isPhaseWhitelisted[_saleId][_phaseId] = true;

                emit MerklePhaseCreated(_saleId, _phaseId);
            }
        }
    }

    function handleMerkleMint(
        uint256 _saleId,
        uint256 _phaseId,
        uint256 _editionId,
        uint256 _maxEditionId,
        uint16 _mintCount,
        address _recipient,
        address _creator,
        address _fundsReceiver
    ) internal {
        require(_mintCount > 0, "Nothing being minted");
        uint256 startId = _editionId + saleMintCount[_saleId];

        for (uint i = 0; i < _mintCount; i++) {
            uint256 tokenId = getNextAvailablePrimarySaleToken(startId, _maxEditionId, _creator);

            // send token to buyer (assumes approval has been made, if not then this will fail)
            koda.safeTransferFrom(_creator, _recipient, tokenId);

            emit MerkleMintFromSale(_saleId, tokenId, _phaseId, _recipient);

            startId = tokenId++;
        }
        _handleSaleFunds(_fundsReceiver, getPlatformSaleCommissionForSale(_saleId));
    }

    function getNextAvailablePrimarySaleToken(uint256 _startId, uint256 _maxEditionId, address creator) internal view returns (uint256 _tokenId) {
        for (uint256 tokenId = _startId; tokenId < _maxEditionId; tokenId++) {
            if (koda.ownerOf(tokenId) == creator) {
                return tokenId;
            }
        }
        revert("Primary market exhausted");
    }

    function getPlatformSaleCommissionForSale(uint256 _saleId) internal view returns (uint256) {
        if (koCommissionOverrideForSale[_saleId].active) {
            return koCommissionOverrideForSale[_saleId].koCommission;
        }
        return platformPrimaryCommission;
    }
}
