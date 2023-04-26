// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IFeePool {
    // Views

    function FEE_ADDRESS() external view returns (address);

    function feesAvailable(address account)
        external
        view
        returns (uint256, uint256);

    function feePeriodDuration() external view returns (uint256);

    function isFeesClaimable(address account) external view returns (bool);

    function targetThreshold() external view returns (uint256);

    function totalFeesAvailable() external view returns (uint256);

    function totalRewardsAvailable() external view returns (uint256);

    // Mutative Functions
    function claimFees() external returns (bool);

    function claimOnBehalf(address claimingForAddress) external returns (bool);

    function closeCurrentFeePeriod() external;
}
