// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.6.12;

import "@openzeppelin/upgrades/contracts/Initializable.sol";

/**
 * @dev Interface poseidon hash function
 */
contract PoseidonUnit {
    function poseidon(uint256[] memory) public pure returns (uint256) {}
}

/**
 * @dev Rollup helper functions
 */
contract HermezHelpers is Initializable {
    PoseidonUnit _insPoseidonUnit2;
    PoseidonUnit _insPoseidonUnit3;
    PoseidonUnit _insPoseidonUnit4;

    uint256 private constant _WORD_SIZE = 32;

    /**
     * @dev Load poseidon smart contract
     * @param _poseidon2Elements Poseidon contract address for 2 elements
     * @param _poseidon3Elements Poseidon contract address for 3 elements
     * @param _poseidon4Elements Poseidon contract address for 4 elements
     */
    function _initializeHelpers(
        address _poseidon2Elements,
        address _poseidon3Elements,
        address _poseidon4Elements
    ) internal initializer {
        _insPoseidonUnit2 = PoseidonUnit(_poseidon2Elements);
        _insPoseidonUnit3 = PoseidonUnit(_poseidon3Elements);
        _insPoseidonUnit4 = PoseidonUnit(_poseidon4Elements);
    }

    /**
     * @dev Hash poseidon for 2 elements
     * @param inputs Poseidon input array of 2 elements
     * @return Poseidon hash
     */
    function _hash2Elements(uint256[] memory inputs)
        internal
        view
        returns (uint256)
    {
        return _insPoseidonUnit2.poseidon(inputs);
    }

    /**
     * @dev Hash poseidon for 3 elements
     * @param inputs Poseidon input array of 3 elements
     * @return Poseidon hash
     */
    function _hash3Elements(uint256[] memory inputs)
        internal
        view
        returns (uint256)
    {
        return _insPoseidonUnit3.poseidon(inputs);
    }

    /**
     * @dev Hash poseidon for 4 elements
     * @param inputs Poseidon input array of 4 elements
     * @return Poseidon hash
     */
    function _hash4Elements(uint256[] memory inputs)
        internal
        view
        returns (uint256)
    {
        return _insPoseidonUnit4.poseidon(inputs);
    }

    /**
     * @dev Hash poseidon for sparse merkle tree nodes
     * @param left Input element array
     * @param right Input element array
     * @return Poseidon hash
     */
    function _hashNode(uint256 left, uint256 right)
        internal
        view
        returns (uint256)
    {
        uint256[] memory inputs = new uint256[](2);
        inputs[0] = left;
        inputs[1] = right;
        return _hash2Elements(inputs);
    }

    /**
     * @dev Hash poseidon for sparse merkle tree final nodes
     * @param key Input element array
     * @param value Input element array
     * @return Poseidon hash1
     */
    function _hashFinalNode(uint256 key, uint256 value)
        internal
        view
        returns (uint256)
    {
        uint256[] memory inputs = new uint256[](3);
        inputs[0] = key;
        inputs[1] = value;
        inputs[2] = 1;
        return _hash3Elements(inputs);
    }

    /**
     * @dev Verify sparse merkle tree proof
     * @param root Root to verify
     * @param siblings Siblings necessary to compute the merkle proof
     * @param key Key to verify
     * @param value Value to verify
     * @return True if verification is correct, false otherwise
     */
    function _smtVerifier(
        uint256 root,
        uint256[] memory siblings,
        uint256 key,
        uint256 value
    ) internal view returns (bool) {
        // Step 2: Calcuate root
        uint256 nextHash = _hashFinalNode(key, value);
        uint256 siblingTmp;
        for (int256 i = int256(siblings.length) - 1; i >= 0; i--) {
            siblingTmp = siblings[uint256(i)];
            bool leftRight = (uint8(key >> i) & 0x01) == 1;
            nextHash = leftRight
                ? _hashNode(siblingTmp, nextHash)
                : _hashNode(nextHash, siblingTmp);
        }

        // Step 3: Check root
        return root == nextHash;
    }

    /**
     * @dev Build entry for the exit tree leaf
     * @param token Token identifier
     * @param nonce nonce parameter, only use 40 bits instead of 48
     * @param balance Balance of the account
     * @param ay Public key babyjubjub represented as point: sign + (Ay)
     * @param ethAddress Ethereum address
     * @return uint256 array with the state variables
     */
    function _buildTreeState(
        uint32 token,
        uint48 nonce,
        uint256 balance,
        uint256 ay,
        address ethAddress
    ) internal pure returns (uint256[] memory) {
        uint256[] memory stateArray = new uint256[](4);

        stateArray[0] = token;
        stateArray[0] |= nonce << 32;
        stateArray[0] |= (ay >> 255) << (32 + 40);
        // build element 2
        stateArray[1] = balance;
        // build element 4
        stateArray[2] = (ay << 1) >> 1; // last bit set to 0
        // build element 5
        stateArray[3] = uint256(ethAddress);
        return stateArray;
    }

    /**
     * @dev Decode half floating precision.
     * Max value encoded with this codification: 0x1F89FDCA17AF0E4E3F46CC0000000 (aprox 116 bits)
     * @param float Float half precision encode number
     * @return Decoded floating half precision
     */
    function _float2Fix(uint16 float) internal pure returns (uint256) {
        uint256 m = float & 0x3FF;
        uint256 e = float >> 11;
        uint256 e5 = (float >> 10) & 1;

        // never overflow, max "e" value is 32
        uint256 exp = 10**e;

        // never overflow, max "fix" value is 1023 * 10^32
        uint256 fix = m * exp;

        if ((e5 == 1) && (e != 0)) {
            fix = fix + (exp / 2);
        }
        return fix;
    }

    /**
     * @dev Retrieve ethereum address from a (defaultMessage + babyjub) signature
     * @param babyjub Public key babyjubjub represented as point: sign + (Ay)
     * @param r Signature parameter
     * @param s Signature parameter
     * @param v Signature parameter
     * @return Ethereum address recovered from the signature
     */
    function _checkSig(
        bytes32 babyjub,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) internal pure returns (address) {
        // from https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/cryptography/ECDSA.sol#L46
        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (281): 0 < s < secp256k1n ÷ 2 + 1, and for v in (282): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        require(
            uint256(s) <=
                0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
            "HermezHelpers::_checkSig: INVALID_S_VALUE"
        );

        bytes32 messageDigest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n98", // 98 bytes --> 66 bytes (string message) + 32 bytes (babyjub)
                "I authorize this babyjubjub key for hermez rollup account creation",
                babyjub
            )
        );
        address ethAddress = ecrecover(messageDigest, v, r, s);

        require(
            ethAddress != address(0),
            "HermezHelpers::_checkSig: INVALID_SIGNATURE"
        );

        return ethAddress;
    }

    /**
     * @dev return information from specific call data info
     * @param posParam parameter number relative to 0 to extract the info
     * @return ptr ptr to the call data position where the actual data starts
     * @return len Length of the data
     */
    function _getCallData(uint256 posParam)
        internal
        pure
        returns (uint256 ptr, uint256 len)
    {
        assembly {
            let pos := add(4, mul(posParam, 32))
            ptr := add(calldataload(pos), 4)
            len := calldataload(ptr)
            ptr := add(ptr, 32)
        }
    }

    /**
     * @dev This package fills at least len zeros in memory and a maximum of len+31
     * @param ptr The position where it starts to fill zeros
     * @param len The minimum quantity of zeros it's added
     */
    function _fillZeros(uint256 ptr, uint256 len) internal pure {
        assembly {
            let ptrTo := ptr
            ptr := add(ptr, len)
            for {

            } lt(ptrTo, ptr) {
                ptrTo := add(ptrTo, 32)
            } {
                mstore(ptrTo, 0)
            }
        }
    }

    /**
     * @dev Copy 'len' bytes from memory address 'src', to address 'dest'.
     * From https://github.com/GNSPS/solidity-bytes-utils/blob/master/contracts/BytesLib.sol
     * @param _preBytes bytes storage
     * @param _postBytes Bytes array memory
     */
    function _concatStorage(bytes storage _preBytes, bytes memory _postBytes)
        internal
    {
        assembly {
            // Read the first 32 bytes of _preBytes storage, which is the length
            // of the array. (We don't need to use the offset into the slot
            // because arrays use the entire slot.)
            let fslot := sload(_preBytes_slot)
            // Arrays of 31 bytes or less have an even value in their slot,
            // while longer arrays have an odd value. The actual length is
            // the slot divided by two for odd values, and the lowest order
            // byte divided by two for even values.
            // If the slot is even, bitwise and the slot with 255 and divide by
            // two to get the length. If the slot is odd, bitwise and the slot
            // with -1 and divide by two.
            let slength := div(
                and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)),
                2
            )
            let mlength := mload(_postBytes)
            let newlength := add(slength, mlength)
            // slength can contain both the length and contents of the array
            // if length < 32 bytes so let's prepare for that
            // v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
            switch add(lt(slength, 32), lt(newlength, 32))
                case 2 {
                    // Since the new array still fits in the slot, we just need to
                    // update the contents of the slot.
                    // uint256(bytes_storage) = uint256(bytes_storage) + uint256(bytes_memory) + new_length
                    sstore(
                        _preBytes_slot,
                        // all the modifications to the slot are inside this
                        // next block
                        add(
                            // we can just add to the slot contents because the
                            // bytes we want to change are the LSBs
                            fslot,
                            add(
                                mul(
                                    div(
                                        // load the bytes from memory
                                        mload(add(_postBytes, 0x20)),
                                        // zero all bytes to the right
                                        exp(0x100, sub(32, mlength))
                                    ),
                                    // and now shift left the number of bytes to
                                    // leave space for the length in the slot
                                    exp(0x100, sub(32, newlength))
                                ),
                                // increase length by the double of the memory
                                // bytes length
                                mul(mlength, 2)
                            )
                        )
                    )
                }
                case 1 {
                    // The stored value fits in the slot, but the combined value
                    // will exceed it.
                    // get the keccak hash to get the contents of the array
                    mstore(0x0, _preBytes_slot)
                    let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                    // save new length
                    sstore(_preBytes_slot, add(mul(newlength, 2), 1))

                    // The contents of the _postBytes array start 32 bytes into
                    // the structure. Our first read should obtain the `submod`
                    // bytes that can fit into the unused space in the last word
                    // of the stored array. To get this, we read 32 bytes starting
                    // from `submod`, so the data we read overlaps with the array
                    // contents by `submod` bytes. Masking the lowest-order
                    // `submod` bytes allows us to add that value directly to the
                    // stored value.

                    let submod := sub(32, slength)
                    let mc := add(_postBytes, submod)
                    let end := add(_postBytes, mlength)
                    let mask := sub(exp(0x100, submod), 1)

                    sstore(
                        sc,
                        add(
                            and(
                                fslot,
                                0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00
                            ),
                            and(mload(mc), mask)
                        )
                    )

                    for {
                        mc := add(mc, 0x20)
                        sc := add(sc, 1)
                    } lt(mc, end) {
                        sc := add(sc, 1)
                        mc := add(mc, 0x20)
                    } {
                        sstore(sc, mload(mc))
                    }

                    mask := exp(0x100, sub(mc, end))

                    sstore(sc, mul(div(mload(mc), mask), mask))
                }
                default {
                    // get the keccak hash to get the contents of the array
                    mstore(0x0, _preBytes_slot)
                    // Start copying to the last used word of the stored array.
                    let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                    // save new length
                    sstore(_preBytes_slot, add(mul(newlength, 2), 1))

                    // Copy over the first `submod` bytes of the new data as in
                    // case 1 above.
                    let slengthmod := mod(slength, 32)
                    let mlengthmod := mod(mlength, 32)
                    let submod := sub(32, slengthmod)
                    let mc := add(_postBytes, submod)
                    let end := add(_postBytes, mlength)
                    let mask := sub(exp(0x100, submod), 1)

                    sstore(sc, add(sload(sc), and(mload(mc), mask)))

                    for {
                        sc := add(sc, 1)
                        mc := add(mc, 0x20)
                    } lt(mc, end) {
                        sc := add(sc, 1)
                        mc := add(mc, 0x20)
                    } {
                        sstore(sc, mload(mc))
                    }

                    mask := exp(0x100, sub(mc, end))

                    sstore(sc, mul(div(mload(mc), mask), mask))
                }
        }
    }
}
