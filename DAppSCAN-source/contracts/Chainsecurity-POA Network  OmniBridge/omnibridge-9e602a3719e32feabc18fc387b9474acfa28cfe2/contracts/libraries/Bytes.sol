pragma solidity 0.7.5;

/**
 * @title Bytes
 * @dev Helper methods to transform bytes to other solidity types.
 */
library Bytes {
    /**
     * @dev Truncate bytes array if its size is more than 20 bytes.
     * NOTE: This function does not perform any checks on the received parameter.
     * Make sure that the _bytes argument has a correct length, not less than 20 bytes.
     * A case when _bytes has length less than 20 will lead to the undefined behaviour,
     * since assembly will read data from memory that is not related to the _bytes argument.
     * @param _bytes to be converted to address type
     * @return addr address included in the firsts 20 bytes of the bytes array in parameter.
     */
    function bytesToAddress(bytes memory _bytes) internal pure returns (address addr) {
        assembly {
            addr := mload(add(_bytes, 20))
        }
    }
}
