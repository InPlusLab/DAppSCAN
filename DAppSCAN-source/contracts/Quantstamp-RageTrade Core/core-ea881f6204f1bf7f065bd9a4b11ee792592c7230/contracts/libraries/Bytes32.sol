// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Bytes32 {
    function slice(
        bytes32 input,
        uint256 start,
        uint256 end
    ) internal pure returns (uint256 val) {
        assembly {
            val := shl(start, input)
            val := shr(add(start, sub(256, end)), val)
        }
    }

    // extracts given least significant bits
    function extract(bytes32 input, uint256 bits) internal pure returns (uint256 value, bytes32 inputUpdated) {
        assembly {
            let shift := sub(256, bits)
            value := shr(shift, shl(shift, input))
            inputUpdated := shr(bits, input)
        }
    }

    function extractAddress(bytes32 input) internal pure returns (address value, bytes32 inputUpdated) {
        uint256 temp;
        (temp, inputUpdated) = extract(input, 160);
        assembly {
            value := temp
        }
    }

    function extractUint16(bytes32 input) internal pure returns (uint16 value, bytes32 inputUpdated) {
        uint256 temp;
        (temp, inputUpdated) = extract(input, 16);
        value = uint16(temp);
    }

    function extractUint32(bytes32 input) internal pure returns (uint32 value, bytes32 inputUpdated) {
        uint256 temp;
        (temp, inputUpdated) = extract(input, 32);
        value = uint32(temp);
    }

    function extractBool(bytes32 input) internal pure returns (bool value, bytes32 inputUpdated) {
        uint256 temp;
        (temp, inputUpdated) = extract(input, 8);
        value = temp != 0;
    }

    function offset(bytes32 key, uint256 offset_) internal pure returns (bytes32) {
        assembly {
            key := add(key, offset_)
        }
        return key;
    }

    function fromUint(uint256 input) internal pure returns (bytes32 output) {
        assembly {
            output := input
        }
    }

    function keccak256One(bytes32 input) internal pure returns (bytes32 result) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0, input)
            result := keccak256(0, 0x20)
        }
    }

    function keccak256Two(bytes32 input1, bytes32 input2) internal pure returns (bytes32 result) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(0, input1)
            mstore(0x20, input2)
            result := keccak256(0, 0x40)
        }
    }
}
