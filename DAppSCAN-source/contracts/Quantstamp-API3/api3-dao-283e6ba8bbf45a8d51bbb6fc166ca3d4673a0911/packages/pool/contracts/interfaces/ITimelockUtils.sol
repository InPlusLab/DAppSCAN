//SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./IClaimUtils.sol";

interface ITimelockUtils is IClaimUtils {
    event DepositedVesting(
        address indexed user,
        uint256 amount,
        uint256 start,
        uint256 end
        );

    event UpdatedTimelock(
        address indexed user,
        address indexed timelockManagerAddress,
        uint256 remainingAmount
        );

    function depositWithVesting(
        address source,
        uint256 amount,
        address userAddress,
        uint256 releaseStart,
        uint256 releaseEnd
        )
        external;

    function updateTimelockStatus(
        address userAddress,
        address timelockManagerAddress
        )
        external;
}
