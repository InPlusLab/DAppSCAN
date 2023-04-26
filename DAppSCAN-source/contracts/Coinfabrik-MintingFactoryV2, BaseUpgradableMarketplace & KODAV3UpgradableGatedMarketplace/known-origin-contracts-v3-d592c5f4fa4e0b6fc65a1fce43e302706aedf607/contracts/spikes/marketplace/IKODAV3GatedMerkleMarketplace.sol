// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IKODAV3GatedMerkleMarketplace {
    /// @notice MerklePhaseMetadata represents a time structured part of a sale, i.e. VIP, pre sale or open sale
    struct MerklePhaseMetadata {
        uint128 startTime; // The start time of the sale as a whole
        uint128 endTime; // The end time of the sale phase, also the beginning of the next phase if applicable
        uint16 walletMintLimit; // The mint limit per wallet for the phase
        uint16 mintCap; // The maximum amount of mints for the phase
        uint128 priceInWei; // Price in wei for one mint
        uint256 maxEditionId; // The maximum ID of an edition
        address creator; // The original edition creator
        address fundsReceiver; // The handler of funds
    }

    /// @notice For an edition, create a new pre-list sale and define merkle root for all phases
    /// @param _editionId ID of the first token in the edition
    /// @param _phaseIds All merkle roots of each phase
    function createMerkleSaleWithPhases(
        uint256 _editionId,
        bytes32[] calldata _phaseIds
    ) external;

    /// @notice Allow a user with a merkle proof to buy a token from a phase of a sale
    /// @param _saleId ID of the edition sale
    /// @param _phaseId Merkle root of the phase
    /// @param _mintCount How many tokens user wishes to purchase
    /// @param _phase Params for the phase verified with the root
    /// @param _recipient Address receiving the dropped token
    /// @param _merkleProof Proof user is part of the phase
    function merkleMint(
        uint256 _saleId,
        bytes32 _phaseId,
        uint16 _mintCount,
        address _recipient,
        MerklePhaseMetadata calldata _phase,
        bytes32[] calldata _merkleProof
    ) payable external;

    /// @notice Add additional phases to a sale
    function addPhasesToMerkleSale(uint256 _saleId, bytes32[] calldata _phaseIds) external;

    /// @notice Remove phases from a sale even when contract is paused
    function removePhasesFromMerkleSale(uint256 _saleId, bytes32[] calldata _phaseIds) external;

    /// @notice checks whether a given user is on the list to mint from a phase
    /// @param _saleId ID of the edition sale
    /// @param _phaseId Merkle root of the phase
    /// @param _account Account eligible for phase
    /// @param _phase Params for the phase verified with the root
    /// @param _merkleProof Proof user is part of the phase
    function onPhaseMerkleList(
        uint256 _saleId,
        bytes32 _phaseId,
        address _account,
        MerklePhaseMetadata calldata _phase,
        bytes32[] calldata _merkleProof
    ) external view returns (bool);

    /// @notice For a given sale phase, how many more NFTs account can purchase
    /// @param _saleId ID of the edition sale
    /// @param _phaseId Merkle root of the phase
    /// @param _account Account eligible for phase
    /// @param _phase Params for the phase verified with the root
    /// @param _merkleProof Proof user is part of the phase
    function remainingMerklePhaseMintAllowance(
        uint256 _saleId,
        bytes32 _phaseId,
        address _account,
        MerklePhaseMetadata calldata _phase,
        bytes32[] calldata _merkleProof
    ) external view returns (uint256);

    function toggleMerkleSalePause(uint256 _saleId) external;
}
