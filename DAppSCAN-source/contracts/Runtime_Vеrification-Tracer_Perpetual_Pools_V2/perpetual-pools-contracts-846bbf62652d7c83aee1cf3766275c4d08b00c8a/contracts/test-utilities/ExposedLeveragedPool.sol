// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "../implementation/LeveragedPool.sol";

contract ExposedLeveragedPool is LeveragedPool {
    function _feeTransfer(uint256 totalFeeAmount) public {
        return feeTransfer(totalFeeAmount);
    }
}
