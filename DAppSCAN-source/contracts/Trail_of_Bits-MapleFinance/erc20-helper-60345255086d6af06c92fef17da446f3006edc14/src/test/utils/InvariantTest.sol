// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

contract InvariantTest {
    
    address[] private targetContracts_;

    function targetContracts() public view returns (address[] memory) {
        require(targetContracts_.length > 0, "NO_TARGET_CONTRACTS");
        return targetContracts_;
    }

    function addTargetContract(address newTargetContract) internal {
        targetContracts_.push(newTargetContract);
    }

}
