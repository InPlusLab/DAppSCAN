pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2; // to enable structure-type parameter

import "../perpetual/PerpetualGovernance.sol";


contract TestPerpGovernance is PerpetualGovernance {
    function testAmmRequired() public view ammRequired returns (uint256) {
        return 1;
    }
}
