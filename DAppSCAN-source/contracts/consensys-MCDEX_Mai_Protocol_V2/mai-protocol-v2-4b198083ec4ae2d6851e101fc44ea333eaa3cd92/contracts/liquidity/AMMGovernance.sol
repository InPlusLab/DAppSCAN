pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "@openzeppelin/contracts/access/roles/WhitelistedRole.sol";

import {LibMathSigned, LibMathUnsigned} from "../lib/LibMath.sol";
import "../lib/LibTypes.sol";


contract AMMGovernance is WhitelistedRole {
    using LibMathSigned for int256;
    using LibMathUnsigned for uint256;

    LibTypes.AMMGovernanceConfig internal governance;

    // auto-set when calling setGovernanceParameter
    int256 public emaAlpha2; // 1 - emaAlpha
    int256 public emaAlpha2Ln; // ln(emaAlpha2)

    event UpdateGovernanceParameter(bytes32 indexed key, int256 value);

    function setGovernanceParameter(bytes32 key, int256 value) public onlyWhitelistAdmin {
        if (key == "poolFeeRate") {
            governance.poolFeeRate = value.toUint256();
        } else if (key == "poolDevFeeRate") {
            governance.poolDevFeeRate = value.toUint256();
        } else if (key == "emaAlpha") {
            require(value > 0, "alpha should be > 0");
            governance.emaAlpha = value;
            emaAlpha2 = 10**18 - governance.emaAlpha;
            emaAlpha2Ln = emaAlpha2.wln();
        } else if (key == "updatePremiumPrize") {
            governance.updatePremiumPrize = value.toUint256();
        } else if (key == "markPremiumLimit") {
            governance.markPremiumLimit = value;
        } else if (key == "fundingDampener") {
            governance.fundingDampener = value;
        } else {
            revert("key not exists");
        }
        emit UpdateGovernanceParameter(key, value);
    }

    function getGovernance() public view returns (LibTypes.AMMGovernanceConfig memory) {
        return governance;
    }
}
