pragma solidity ^0.6.2;

import "./PEAKDEFI_V1.sol";


contract PEAKDEFI_V2 is PEAKDEFI_V1 {
    function changeTokenData(string calldata newName, string calldata symbol, uint8 newDecimal) external {
        _initialize(newName, symbol, newDecimal);
    }
}