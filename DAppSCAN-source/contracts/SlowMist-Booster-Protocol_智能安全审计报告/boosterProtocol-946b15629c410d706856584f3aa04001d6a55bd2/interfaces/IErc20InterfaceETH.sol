// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IErc20InterfaceETH {

    /*** User Interface ***/
    function underlying() external view returns (address);

    function mint() external payable;
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow() external payable;

    function isNativeToken() external pure returns (bool);
}