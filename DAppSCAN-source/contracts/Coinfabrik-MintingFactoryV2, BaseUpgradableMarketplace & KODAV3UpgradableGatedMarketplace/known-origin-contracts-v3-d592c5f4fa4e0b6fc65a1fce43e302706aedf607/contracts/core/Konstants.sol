// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

contract Konstants {

    // Every edition always goes up in batches of 1000
    uint16 public constant MAX_EDITION_SIZE = 1000;

    // magic method that defines the maximum range for an edition - this is fixed forever - tokens are minted in range
    function _editionFromTokenId(uint256 _tokenId) internal pure returns (uint256) {
        return (_tokenId / MAX_EDITION_SIZE) * MAX_EDITION_SIZE;
    }
}
