// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {IERC721Ownable} from "./IERC721Ownable.sol";

// Based on https://eips.ethereum.org/EIPS/eip-2612 ERC-20 permit style but for erc-721 tokens
// Variant assumes "value" param replaced with "tokenId" due to non-fungible nature

interface INFTPermit {
    function permit(address owner, address spender, uint256 tokenId, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}

// FIXME - can we use this for cheapness? - https://github.com/0xProject/0x-monorepo/blob/development/contracts/utils/contracts/src/LibEIP712.sol
abstract contract NFTPermit is INFTPermit {

    // FIXME - does this mapping need to be a mapping from address to token id to permit nonce ?
    // mapping(address => mapping(uint256 => uint256)) public permitNonces;

    // ERC-2612-style permit nonces
    mapping(address => uint256) public nonces;

    // keccak256("Permit(address owner,address spender,uint256 tokenId,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x48d39b37a35214940203bbbd4f383519797769b13d936f387d89430afef27688;

    function permit(address owner, address spender, uint256 tokenId, uint deadline, uint8 v, bytes32 r, bytes32 s)
    override
    external {
        require(deadline != 0 && deadline >= block.timestamp, "Deadline expired");
        require(IERC721Ownable(address(this)).ownerOf(tokenId) == owner, "Invalid owner");

        // Create digest to check signatures
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparator(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, tokenId, nonces[owner]++, deadline))
            )
        );

        // Has the original signer signed it
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNATURE");

        // set approval for signature if passed
        _approval(owner, spender, tokenId);
    }

    function _domainSeparator() internal virtual returns (bytes32);

    function _approval(address _owner, address _approved, uint256 _tokenId) internal virtual;
}
