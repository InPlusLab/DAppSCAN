pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "../lib/LibOrder.sol";
import "../lib/LibTypes.sol";
import "../interface/IPerpetualProxy.sol";
import {LibMathSigned, LibMathUnsigned} from "../lib/LibMath.sol";

contract TestFundingMock {
    using LibMathUnsigned for uint256;

    uint256 public _markPrice;
    int256 public _accumulatedFundingPerContract;
    uint256 public constant ONE = 1e18;

    function setMarkPrice(uint256 price) public returns (uint256) {
        _markPrice = price;
    }

    function setInversedMarkPrice(uint256 price) public returns (uint256) {
        _markPrice = ONE.wdiv(price);
    }

    function currentMarkPrice() public view returns (uint256) {
        return _markPrice;
    }

    function setAccumulatedFundingPerContract(int256 newValue) public {
        _accumulatedFundingPerContract = newValue;
    }

    function currentAccumulatedFundingPerContract() public view returns (int256) {
        return _accumulatedFundingPerContract;
    }

    int256 dummy; // in order to prevent seeing "can be restricted to pure"

    function perpetualProxy() external view returns (IPerpetualProxy) {
        if (dummy == 0) {
            return IPerpetualProxy(address(0x0000000000000000000000000000000000000111));
        }

        // never be here
        return IPerpetualProxy(address(0x0000000000000000000000000000000000000000));
    }
}
