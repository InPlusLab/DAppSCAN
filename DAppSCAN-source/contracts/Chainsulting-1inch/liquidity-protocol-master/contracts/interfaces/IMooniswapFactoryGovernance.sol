// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;


interface IMooniswapFactoryGovernance {
    function shareParameters() external view returns(uint256 referralShare, uint256 governanceShare, address governanceFeeReceiver, address referralFeeReceiver);
    function defaults() external view returns(uint256 defaultFee, uint256 defaultSlippageFee, uint256 defaultDecayPeriod);

    function defaultFee() external view returns(uint256);
    function defaultSlippageFee() external view returns(uint256);
    function defaultDecayPeriod() external view returns(uint256);
    function referralShare() external view returns(uint256);
    function governanceShare() external view returns(uint256);
    function governanceFeeReceiver() external view returns(address);
    function referralFeeReceiver() external view returns(address);

    function isFeeReceiver(address) external view returns(bool);
}
