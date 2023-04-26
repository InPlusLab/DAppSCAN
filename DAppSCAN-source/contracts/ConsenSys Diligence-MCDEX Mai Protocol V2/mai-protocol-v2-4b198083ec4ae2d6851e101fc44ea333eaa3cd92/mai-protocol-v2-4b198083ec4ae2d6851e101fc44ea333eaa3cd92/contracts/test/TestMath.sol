pragma solidity ^0.5.2;

import {LibMathSigned, LibMathUnsigned} from "../lib/LibMath.sol";


contract TestSignedMath {
    using LibMathSigned for int256;

    function wfrac(int256 a, int256 b, int256 c) public pure returns (int256) {
        return a.wfrac(b, c);
    }

    function wmul(int256 a, int256 b) public pure returns (int256) {
        return a.wmul(b);
    }

    function wdiv(int256 a, int256 b) public pure returns (int256) {
        return a.wdiv(b);
    }

    function ceil(int256 a, int256 m) public pure returns (int256) {
        return a.ceil(m);
    }

    function wpowi(int256 x, int256 y) public pure returns (int256) {
        return x.wpowi(y);
    }

    function roundHalfUp(int256 v, int256 t) public pure returns (int256) {
        return v.roundHalfUp(t);
    }

    function wln(int256 x) public pure returns (int256) {
        return x.wln();
    }

    function logBase(int256 b, int256 x) public pure returns (int256) {
        return b.logBase(x);
    }

    function mul(int256 a, int256 b) public pure returns (int256) {
        return a.mul(b);
    }

    function div(int256 a, int256 b) public pure returns (int256) {
        return a.div(b);
    }

    function sub(int256 a, int256 b) public pure returns (int256) {
        return a.sub(b);
    }

    function add(int256 a, int256 b) public pure returns (int256) {
        return a.add(b);
    }

    function toUint256(int256 x) public pure returns (uint256) {
        return x.toUint256();
    }
}


contract TestUnsignedMath {
    using LibMathUnsigned for uint256;

    function WAD() public pure returns (uint256) {
        return LibMathUnsigned.WAD();
    }

    function wfrac(uint256 a, uint256 b, uint256 c) public pure returns (uint256) {
        return a.wfrac(b, c);
    }

    function add(uint256 a, uint256 b) public pure returns (uint256) {
        return a.add(b);
    }

    function wmul(uint256 a, uint256 b) public pure returns (uint256) {
        return a.wmul(b);
    }

    function div(uint256 a, uint256 b) public pure returns (uint256) {
        return a.div(b);
    }

    function wdiv(uint256 a, uint256 b) public pure returns (uint256) {
        return a.wdiv(b);
    }

    function max(uint256 x, uint256 y) public pure returns (uint256 z) {
        return x.max(y);
    }

    function mod(uint256 x, uint256 m) public pure returns (uint256) {
        return x.mod(m);
    }

    function ceil(uint256 x, uint256 m) public pure returns (uint256) {
        return x.ceil(m);
    }
}
