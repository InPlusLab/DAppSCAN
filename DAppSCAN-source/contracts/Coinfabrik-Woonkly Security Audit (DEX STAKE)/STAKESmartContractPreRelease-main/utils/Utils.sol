// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;



library Utils {


function getStringLen(string memory str)  internal pure returns (uint){
    bytes memory tempEmptyStringTest = bytes(str); // Uses memory
    return tempEmptyStringTest.length;
}


 function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
    if (_i == 0) {
        return "0";
    }
    uint j = _i;
    uint len;
    while (j != 0) {
        len++;
        j /= 10;
    }
    bytes memory bstr = new bytes(len);
    uint k = len - 1;
    while (_i != 0) {
        bstr[k--] = byte(uint8(48 + _i % 10));
        _i /= 10;
    }
    return string(bstr);
}


function append(string memory a, string memory b, string memory c, string memory d, string memory e) internal pure returns (string memory) {

    return string(abi.encodePacked(a, b, c, d, e));

}


function checkEven(uint testNo) internal  pure returns(bool){
        uint remainder = testNo%2;
        if(remainder==0)
            return true;
        else
            return false;
    }
    
}






