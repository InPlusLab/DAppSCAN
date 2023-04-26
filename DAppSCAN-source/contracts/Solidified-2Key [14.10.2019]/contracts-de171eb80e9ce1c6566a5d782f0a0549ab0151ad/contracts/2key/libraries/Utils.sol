pragma solidity ^0.4.0;

/**
 * @title Utils
 * @dev Utility functions to perform various repeated actions in contracts
 */
contract Utils {

    /**
     * @notice Function to transform string to bytes32
     * @dev string should be less than 32 chars
     */
    function stringToBytes32(
        string memory source
    )
    internal
    pure
    returns (bytes32 result)
    {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }
        assembly {
            result := mload(add(source, 32))
        }
    }

    /**
     * @notice Function to concat at most 3 strings
     * @dev If you want to handle concatenation of less than 3, then pass first their values and for the left pass empty strings
     * @return string concatenated
     */
    function strConcat(
        string _a,
        string _b,
        string _c
    )
    internal
    pure
    returns (string)
    {
        bytes memory _ba = bytes(_a);
        bytes memory _bb = bytes(_b);
        bytes memory _bc = bytes(_c);
        string memory abcde = new string(_ba.length + _bb.length + _bc.length);
        bytes memory babcde = bytes(abcde);
        uint k = 0;
        for (uint i = 0; i < _ba.length; i++) babcde[k++] = _ba[i];
        for (i = 0; i < _bb.length; i++) babcde[k++] = _bb[i];
        for (i = 0; i < _bc.length; i++) babcde[k++] = _bc[i];
        return string(babcde);
    }


}
