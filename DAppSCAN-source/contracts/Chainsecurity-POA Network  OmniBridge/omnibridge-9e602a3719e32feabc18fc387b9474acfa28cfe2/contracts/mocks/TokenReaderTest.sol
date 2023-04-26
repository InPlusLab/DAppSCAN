/* solhint-disable */
pragma solidity 0.7.5;

import "../libraries/TokenReader.sol";

contract Token1 {
    function name() external pure returns (string memory) {
        return "Token";
    }

    function symbol() external pure returns (string memory) {
        return "TKN";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}

contract Token2 {
    function NAME() external pure returns (string memory) {
        return "Token";
    }

    function SYMBOL() external pure returns (string memory) {
        return "TKN";
    }

    function DECIMALS() external pure returns (uint8) {
        return 18;
    }
}

contract Token3 {
    function name() external pure returns (bytes32) {
        return bytes32("Token");
    }

    function symbol() external pure returns (bytes32) {
        return bytes32("TKN");
    }

    function decimals() external pure returns (uint256) {
        return 9;
    }
}

contract Token4 {
    function NAME() external pure returns (bytes32) {
        return bytes32("Token");
    }

    function SYMBOL() external pure returns (bytes32) {
        return bytes32("TKN");
    }
}

contract Token5 {
    function name() external pure returns (bytes32) {
        return bytes32("0123456789abcdef0123456789abcdef");
    }

    function SYMBOL() external pure returns (bytes32) {
        return bytes32("0123456789abcdef0123456789abcdef");
    }
}

contract Token6 {
    function NAME() external pure returns (string memory) {
        return "0123456789abcdef0123456789abcdefX";
    }

    function symbol() external pure returns (string memory) {
        return "0123456789abcdef0123456789abcdefY";
    }
}

contract Token7 {
    function symbol() external pure returns (string memory) {
        return "";
    }

    function decimals() external pure returns (uint8) {
        return 0;
    }
}

contract Token8 {
    fallback() external {
        revert("Error message");
    }
}

contract TokenReaderTest {
    function test1() external {
        address token = address(new Token1());

        require(keccak256(abi.encodePacked(TokenReader.readName(token))) == keccak256("Token"));
        require(keccak256(abi.encodePacked(TokenReader.readSymbol(token))) == keccak256("TKN"));
        require(TokenReader.readDecimals(token) == 18);
    }

    function test2() external {
        address token = address(new Token2());

        require(keccak256(abi.encodePacked(TokenReader.readName(token))) == keccak256("Token"));
        require(keccak256(abi.encodePacked(TokenReader.readSymbol(token))) == keccak256("TKN"));
        require(TokenReader.readDecimals(token) == 18);
    }

    function test3() external {
        address token = address(new Token3());

        require(keccak256(abi.encodePacked(TokenReader.readName(token))) == keccak256("Token"));
        require(keccak256(abi.encodePacked(TokenReader.readSymbol(token))) == keccak256("TKN"));
        require(TokenReader.readDecimals(token) == 9);
    }

    function test4() external {
        address token = address(new Token4());

        require(keccak256(abi.encodePacked(TokenReader.readName(token))) == keccak256("Token"));
        require(keccak256(abi.encodePacked(TokenReader.readSymbol(token))) == keccak256("TKN"));
        require(TokenReader.readDecimals(token) == 0);
    }

    function test5() external {
        address token = address(new Token5());

        require(keccak256(abi.encodePacked(TokenReader.readName(token))) == keccak256("0123456789abcdef0123456789abcdef"));
        require(keccak256(abi.encodePacked(TokenReader.readSymbol(token))) == keccak256("0123456789abcdef0123456789abcdef"));
        require(TokenReader.readDecimals(token) == 0);
    }

    function test6() external {
        address token = address(new Token6());

        require(keccak256(abi.encodePacked(TokenReader.readName(token))) == keccak256("0123456789abcdef0123456789abcdefX"));
        require(keccak256(abi.encodePacked(TokenReader.readSymbol(token))) == keccak256("0123456789abcdef0123456789abcdefY"));
        require(TokenReader.readDecimals(token) == 0);
    }

    function test7() external {
        address token = address(new Token7());

        require(keccak256(abi.encodePacked(TokenReader.readName(token))) == keccak256(""));
        require(keccak256(abi.encodePacked(TokenReader.readSymbol(token))) == keccak256(""));
        require(TokenReader.readDecimals(token) == 0);
    }

    function test8() external {
        address token = address(new Token8());

        require(keccak256(abi.encodePacked(TokenReader.readName(token))) == keccak256(""));
        require(keccak256(abi.encodePacked(TokenReader.readSymbol(token))) == keccak256(""));
        require(TokenReader.readDecimals(token) == 0);
    }
}
/* solhint-enable */
