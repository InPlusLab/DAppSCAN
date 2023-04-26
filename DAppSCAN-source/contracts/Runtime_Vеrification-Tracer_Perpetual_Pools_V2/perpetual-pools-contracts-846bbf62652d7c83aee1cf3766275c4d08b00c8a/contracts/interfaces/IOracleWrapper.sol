//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity 0.8.7;

/// @title The oracle wrapper contract interface
interface IOracleWrapper {
    function oracle() external view returns (address);

    function deployer() external view returns (address);

    // #### Functions

    /**
     * @notice Returns the current price for the asset in question
     * @return The latest price
     */
    function getPrice() external view returns (int256);

    /**
     * @return _price The latest round data price
     * @return _data The metadata. Implementations can choose what data to return here
     */
    function getPriceAndMetadata() external view returns (int256 _price, bytes memory _data);

    /**
     * @notice Converts from a WAD to normal value
     * @return Converted non-WAD value
     */
    function fromWad(int256 wad) external view returns (int256);

    /**
     * @notice Updates the underlying oracle state and returns the new price
     * @dev Spot oracles must implement but it will be a no-op
     */
    function poll() external returns (int256);
}
