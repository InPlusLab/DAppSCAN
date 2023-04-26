// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface ITokenUriResolver {

    /// @notice Return the edition or token level URI - token level trumps edition level if found
    function tokenURI(uint256 _editionId, uint256 _tokenId) external view returns (string memory);

    /// @notice Do we have an edition level or token level token URI resolver set
    function isDefined(uint256 _editionId, uint256 _tokenId) external view returns (bool);
}
