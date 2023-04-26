// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.6.12;

import "../lib/HermezHelpers.sol";

contract HermezHelpersTest is HermezHelpers {
    constructor(
        address _poseidon2Elements,
        address _poseidon3Elements,
        address _poseidon4Elements
    ) public {
        _initializeHelpers(
            _poseidon2Elements,
            _poseidon3Elements,
            _poseidon4Elements
        );
    }

    function testHash2Elements(uint256[] memory inputs)
        public
        view
        returns (uint256)
    {
        return _hash2Elements(inputs);
    }

    function testHash3Elements(uint256[] memory inputs)
        public
        view
        returns (uint256)
    {
        return _hash3Elements(inputs);
    }

    function testHash4Elements(uint256[] memory inputs)
        public
        view
        returns (uint256)
    {
        return _hash4Elements(inputs);
    }

    function testHashNode(uint256 left, uint256 right)
        public
        view
        returns (uint256)
    {
        return _hashNode(left, right);
    }

    function testHashFinalNode(uint256 key, uint256 value)
        public
        view
        returns (uint256)
    {
        return _hashFinalNode(key, value);
    }

    function smtVerifierTest(
        uint256 root,
        uint256[] memory siblings,
        uint256 key,
        uint256 value
    ) public view returns (bool) {
        return _smtVerifier(root, siblings, key, value);
    }

    function buildTreeStateTest(
        uint32 token,
        uint48 nonce, // 40 bits
        uint256 balance,
        uint256 ay,
        address ethAddress
    ) public pure returns (uint256[] memory) {
        uint256[] memory arrayState = _buildTreeState(
            token,
            nonce,
            balance,
            ay,
            ethAddress
        );
        return (arrayState);
    }

    function hashTreeStateTest(
        uint32 token,
        uint16 nonce,
        uint256 balance,
        uint256 ay,
        address ethAddress
    ) public view returns (uint256) {
        uint256[] memory arrayState = _buildTreeState(
            token,
            nonce,
            balance,
            ay,
            ethAddress
        );
        return _hash4Elements(arrayState);
    }

    function float2FixTest(uint16 float) public pure returns (uint256) {
        return _float2Fix(float);
    }

    function checkSigTest(
        bytes32 babyjub,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) public pure returns (address) {
        return _checkSig(babyjub, r, s, v);
    }
}
