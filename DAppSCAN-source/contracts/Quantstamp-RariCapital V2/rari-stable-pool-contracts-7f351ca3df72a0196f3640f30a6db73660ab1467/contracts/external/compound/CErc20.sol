// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.5.17;

/**
 * @title Compound's CErc20 Contract
 * @notice CTokens which wrap an EIP-20 underlying
 * @author Compound
 */
interface CErc20 {
    function underlying() external view returns (address);
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function balanceOfUnderlying(address owner) external returns (uint);
    function accrueInterest() external returns (uint);
    function exchangeRateStored() external view returns (uint);
    function transfer(address dst, uint256 amount) external returns (bool);
}
