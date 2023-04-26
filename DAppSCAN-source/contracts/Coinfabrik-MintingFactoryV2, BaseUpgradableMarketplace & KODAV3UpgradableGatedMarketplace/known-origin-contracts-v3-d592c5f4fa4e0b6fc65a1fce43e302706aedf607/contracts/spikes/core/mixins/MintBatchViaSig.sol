// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

// FIXME add new Mint signature variant method for consecutive batch mint

// TODO test minting logic
abstract contract MintBatchViaSig {

    // TODO generate properly
    // keccak256("MintBatchViaSig(uint96 editionSize, address to, string uri, uint256 nonce, uint256 deadline)");
    bytes32 public constant MINT_BATCH_TYPEHASH = 0x48d39b37a35214940203bbbd4f383519797769b13d936f387d89430afef27688;

    // Signature based minting nonces
    mapping(address => uint256) public mintingNonces;

    // Mints batches of tokens emitting multiple Transfer events - via signed payloads
    function mintBatchEditionViaSig(uint96 _editionSize, address _to, string calldata _uri, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    public returns
    (uint256 _editionId) {
        require(deadline != 0 && deadline >= block.timestamp, "Deadline expired");
        require(_hasMinterRole(_to), "Minter not approved");

        uint256 currentNonce = mintingNonces[_to];

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _domainSeparator(),
                keccak256(abi.encode(MINT_BATCH_TYPEHASH, _editionSize, _to, _uri, currentNonce, deadline))
            )
        );

        // Has the original signer signed it
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == _to, "INVALID_SIGNATURE");

        mintingNonces[_to]++;

        return _mintBatchEdition(_editionSize, _to, _uri);
    }

    function _domainSeparator() internal virtual returns (bytes32);

    function _hasMinterRole(address _minter) internal virtual returns (bool);

    function _mintBatchEdition(uint96 _editionSize, address _to, string calldata _uri) internal virtual returns (uint256);
}
