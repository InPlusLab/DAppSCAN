// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/// @notice Common interface to the edition royalties registry
interface ICollabRoyaltiesRegistry {

    /// @notice Creates & deploys a new royalties recipient, cloning _handle and setting it up with the provided _recipients and _splits
    function createRoyaltiesRecipient(
        address _handler,
        address[] calldata _recipients,
        uint256[] calldata _splits
    ) external returns (address deployedHandler);

    /// @notice Sets up the provided edition to use the provided _recipient
    function useRoyaltiesRecipient(uint256 _editionId, address _deployedHandler) external;

    /// @notice Setup a royalties handler but does not deploy it, uses predicable clone and sets this against the edition
    function usePredeterminedRoyaltiesRecipient(
        uint256 _editionId,
        address _handler,
        address[] calldata _recipients,
        uint256[] calldata _splits
    ) external;

    /// @notice Deploy and setup a royalties recipient for the given edition
    function createAndUseRoyaltiesRecipient(
        uint256 _editionId,
        address _handler,
        address[] calldata _recipients,
        uint256[] calldata _splits
    )
    external returns (address deployedHandler);

    /// @notice Predict the deployed clone address with the given parameters
    function predictedRoyaltiesHandler(
        address _handler,
        address[] calldata _recipients,
        uint256[] calldata _splits
    ) external view returns (address predictedHandler);

}
