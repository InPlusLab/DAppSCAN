pragma solidity 0.5.10;

library StringComparator {
    function compareStrings (string memory a, string memory b) public pure
       returns (bool) {
        return keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b)));
    }
}
