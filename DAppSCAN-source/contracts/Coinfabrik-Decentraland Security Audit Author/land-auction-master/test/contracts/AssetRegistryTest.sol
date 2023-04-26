pragma solidity ^0.4.24;

import "openzeppelin-eth/contracts/token/ERC721/ERC721.sol";


contract AssetRegistryTest is ERC721 {
    uint256 constant clearLow = 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000;
    uint256 constant clearHigh = 0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff;
    uint256 constant factor = 0x100000000000000000000000000000000;

    constructor() public {
        ERC721.initialize();
    }

    function assignMultipleParcels(int[] x, int[] y, address beneficiary) external {
        for (uint256 i = 0; i < x.length; i++) {
            super._mint(beneficiary,  _encodeTokenId(x[i], y[i]));	
        }
    }

    function _encodeTokenId(int x, int y) public pure returns (uint256 result) {
        return _unsafeEncodeTokenId(x, y);
    }

    function _unsafeEncodeTokenId(int x, int y) internal pure returns (uint256) {
        return ((uint(x) * factor) & clearLow) | (uint(y) & clearHigh);
    }
}