// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../../core/IERC2981.sol";

interface ITokenRoyaltiesRegistry is IERC2981 {

    // get total payable royalties recipients
    function totalPotentialRoyalties(uint256 _tokenId) external view returns (uint256);

    // get total payable royalties recipients
    function royaltyParticipantAtIndex(uint256 _tokenId, uint256 _index) external view returns (address, uint256);

    // immutable single time only call - call on token creation by default
    function defineRoyalty(uint256 _tokenId, address _recipient, uint256 _amount) external;

    // enable staged multi-sig style approved joint royalty
    function initMultiOwnerRoyalty(uint256 _tokenId, address _defaultRecipient, uint256 _defaultRoyalty, address[] calldata _recipients, uint256[] calldata _amounts) external;

    // confirm token share - approve use of joint holder
    function confirm(uint256 _tokenId, uint8[] calldata _sigV, bytes32[] calldata _sigR, bytes32[] calldata _sigS) external;

    // reject token share - removes from potential multi-sig address
    function reject(uint256 _tokenId, uint256 _quitterIndex) external;
}

