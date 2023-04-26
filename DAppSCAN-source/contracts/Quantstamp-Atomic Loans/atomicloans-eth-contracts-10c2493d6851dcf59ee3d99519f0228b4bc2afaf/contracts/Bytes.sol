pragma solidity ^0.5.10;

contract Bytes {
    function scriptNumSize(uint256 i) public pure returns (uint256) {
        if      (i > 0x7fffffff) { return 5; }
        else if (i > 0x7fffff  ) { return 4; }
        else if (i > 0x7fff    ) { return 3; }
        else if (i > 0x7f      ) { return 2; }
        else if (i > 0x00      ) { return 1; }
        else                     { return 0; }
    }

    function scriptNumSizeHex(uint256 i) public pure returns (bytes memory) {
        return toBytes(scriptNumSize(i));
    }

    function toBytes(uint256 x) public pure returns (bytes memory b) {
        uint a = scriptNumSize(x);
        b = new bytes(a);
        for (uint i = 0; i < a; i++) {
            b[i] = byte(uint8(x / (2**(8*(a - 1 - i)))));
        }
    }

    function scriptNumEncode(uint256 num) public pure returns (bytes memory) {
        uint a = scriptNumSize(num);
        bytes memory b = toBytes(num);
        for (uint i = 0; i < (a/2); i++) {
            byte c = b[i];
            b[i] = b[a - i - 1];
            b[a - i - 1] = c;
        }
        return b;
    }
}
