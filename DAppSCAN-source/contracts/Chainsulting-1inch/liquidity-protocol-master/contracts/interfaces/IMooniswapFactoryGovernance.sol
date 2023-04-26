// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

/// @title Describes methods that provide all the information about current governance contract state
interface IMooniswapFactoryGovernance {
    /// @notice Returns information about mooniswap shares
    /// @return referralShare Referrals share
    /// @return governanceShare Governance share
    /// @return governanceWallet Governance wallet address
    /// @return referralFeeReceiver Fee collector address
    function shareParameters() external view returns(uint256 referralShare, uint256 governanceShare, address governanceWallet, address referralFeeReceiver);
    /// @notice Initial settings that contract was created
    /// @return defaultFee Default fee
    /// @return defaultSlippageFee Default slippage fee
    /// @return defaultDecayPeriod Decay period for virtual amounts
    function defaults() external view returns(uint256 defaultFee, uint256 defaultSlippageFee, uint256 defaultDecayPeriod);

    /// @notice Same as `defaults` but only returns fee
    function defaultFee() external view returns(uint256);
    /// @notice Same as `defaults` but only returns slippage fee
    function defaultSlippageFee() external view returns(uint256);
    /// @notice Same as `defaults` but only returns decay period
    function defaultDecayPeriod() external view returns(uint256);

    /// @notice Describes previous default fee that had place, current one and time on which this changed
    function virtualDefaultFee() external view returns(uint104, uint104, uint48);
    /// @notice Describes previous default slippage fee that had place, current one and time on which this changed
    function virtualDefaultSlippageFee() external view returns(uint104, uint104, uint48);
    /// @notice Describes previous default decay amount that had place, current one and time on which this changed
    function virtualDefaultDecayPeriod() external view returns(uint104, uint104, uint48);

    /// @notice Same as `shareParameters` but only returns referral share
    function referralShare() external view returns(uint256);
    /// @notice Same as `shareParameters` but only returns governance share
    function governanceShare() external view returns(uint256);
    /// @notice Same as `shareParameters` but only returns governance wallet address
    function governanceWallet() external view returns(address);
    /// @notice Same as `shareParameters` but only returns fee collector address
    function feeCollector() external view returns(address);

    /// @notice True if address is current fee collector or was in the past. Otherwise, false
    function isFeeCollector(address) external view returns(bool);
    /// @notice True if contract is currently working and wasn't stopped. Otherwise, false
    function isActive() external view returns (bool);
}
