// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice This is purely an extension for the KO platform
/// @notice Royalties on KO are defined at an edition level for all tokens from the same edition
interface IERC2981EditionExtension {

    /// @notice Does the edition have any royalties defined
    function hasRoyalties(uint256 _editionId) external view returns (bool);

    /// @notice Get the royalty receiver - all royalties should be sent to this account if not zero address
    function getRoyaltiesReceiver(uint256 _editionId) external view returns (address);
}

/**
 * ERC2981 standards interface for royalties
 */
interface IERC2981 is IERC165, IERC2981EditionExtension {
    /// ERC165 bytes to add to interface array - set in parent contract
    /// implementing this standard
    ///
    /// bytes4(keccak256("royaltyInfo(uint256,uint256)")) == 0x2a55205a
    /// bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
    /// _registerInterface(_INTERFACE_ID_ERC2981);

    /// @notice Called with the sale price to determine how much royalty
    //          is owed and to whom.
    /// @param _tokenId - the NFT asset queried for royalty information
    /// @param _value - the sale price of the NFT asset specified by _tokenId
    /// @return _receiver - address of who should be sent the royalty payment
    /// @return _royaltyAmount - the royalty payment amount for _value sale price
    function royaltyInfo(
        uint256 _tokenId,
        uint256 _value
    ) external view returns (
        address _receiver,
        uint256 _royaltyAmount
    );

}
