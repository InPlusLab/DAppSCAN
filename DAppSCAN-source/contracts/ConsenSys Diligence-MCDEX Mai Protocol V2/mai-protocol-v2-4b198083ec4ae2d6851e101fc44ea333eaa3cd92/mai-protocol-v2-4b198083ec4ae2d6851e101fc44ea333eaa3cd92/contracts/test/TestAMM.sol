pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibMathSigned, LibMathUnsigned} from "../lib/LibMath.sol";
import "../liquidity/AMM.sol";
import "../lib/LibTypes.sol";
import "../lib/LibOrder.sol";
import "./TestPerpetual.sol";

contract TestAMM is AMM {
    uint256 public mockBlockTimestamp;

    constructor(address _perpetualProxy, address _priceFeeder, address token)
        public
        AMM(_perpetualProxy, _priceFeeder, token)
    {
        // solium-disable-next-line security/no-block-members
        mockBlockTimestamp = block.timestamp;
    }

    function setAccumulatedFundingPerContract(int256 newValue) public {
        fundingState.accumulatedFundingPerContract = newValue;
    }

    function getBlockTimestamp() internal view returns (uint256) {
        return mockBlockTimestamp;
    }

    function setBlockTimestamp(uint256 newValue) public {
        mockBlockTimestamp = newValue;
    }

    function timeOnFundingCurvePublic(
        int256 y,
        int256 v0, // lastEMAPremium
        int256 _lastPremium
    )
        public
        view
        returns (
            int256 t // normal int, not WAD
        )
    {
        return timeOnFundingCurve(y, v0, _lastPremium);
    }

    // sum emaPremium curve between [x, y)
    function integrateOnFundingCurvePublic(
        int256 x, // normal int, not WAD
        int256 y, // normal int, not WAD
        int256 v0, // lastEMAPremium
        int256 _lastPremium
    ) public view returns (int256 r) {
        return integrateOnFundingCurve(x, y, v0, _lastPremium);
    }

    function getAccumulatedFundingPublic(
        int256 n, // time span. normal int, not WAD
        int256 v0, // lastEMAPremium
        int256 _lastPremium,
        int256 _lastIndexPrice
    )
        public
        view
        returns (
            int256 vt, // new LastEMAPremium
            int256 acc
        )
    {
        return getAccumulatedFunding(n, v0, _lastPremium, _lastIndexPrice);
    }

    function forceSetFunding(LibTypes.FundingState memory state) public {
        fundingState = state;
    }
}
