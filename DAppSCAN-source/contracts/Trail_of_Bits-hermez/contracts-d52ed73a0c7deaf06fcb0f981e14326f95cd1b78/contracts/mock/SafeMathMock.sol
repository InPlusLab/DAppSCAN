// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.6.12;

import "../math/SafeMathUint128.sol";

contract SafeMathMock {
    using SafeMath128 for uint128;

    function testAdd() public pure returns (uint128) {
        uint128 a = 6;
        uint128 b = 5;
        return a.add(b);
    }

    function testSub() public pure returns (uint128) {
        uint128 a = 6;
        uint128 b = 5;
        return (a).sub(b);
    }

    function testMul() public pure returns (uint128) {
        uint128 a = 6;
        uint128 b = 5;
        return (a).mul(b);
    }

    function testMul0() public pure returns (uint128) {
        uint128 a = 0;
        uint128 b = 5;
        return (a).mul(b);
    }

    function testDiv() public pure returns (uint128) {
        uint128 a = 10;
        uint128 b = 5;
        return (a).div(b);
    }

    function testMod() public pure returns (uint128) {
        uint128 a = 10;
        uint128 b = 5;
        return (a).mod(b);
    }

    function testAddRevert() public pure returns (uint128) {
        uint128 MAX_INT = uint128(-1);
        return MAX_INT.add(MAX_INT);
    }

    function testSubRevert() public pure returns (uint128) {
        uint128 b = 6;
        uint128 a = b - 1;
        return (a).sub(b);
    }

    function testMulRevert() public pure returns (uint128) {
        uint128 MAX_INT = uint128(-1);
        return (MAX_INT).mul(2);
    }

    function testDivRevert() public pure returns (uint128) {
        uint128 a = 5;
        return (a).div(0);
    }

    function testModRevert() public pure returns (uint128) {
        uint128 a = 5;
        return (a).mod(0);
    }
}
