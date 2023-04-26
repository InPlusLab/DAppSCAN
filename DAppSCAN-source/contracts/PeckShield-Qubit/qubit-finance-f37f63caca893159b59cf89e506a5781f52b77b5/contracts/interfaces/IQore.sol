// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../library/QConstant.sol";

interface IQore {
    function qValidator() external view returns (address);

    function getTotalUserList() external view returns (address[] memory);

    function allMarkets() external view returns (address[] memory);

    function marketListOf(address account) external view returns (address[] memory);

    function marketInfoOf(address qToken) external view returns (QConstant.MarketInfo memory);

    function liquidationIncentive() external view returns (uint);

    function checkMembership(address account, address qToken) external view returns (bool);

    function enterMarkets(address[] memory qTokens) external;

    function exitMarket(address qToken) external;

    function supply(address qToken, uint underlyingAmount) external payable returns (uint);

    function redeemToken(address qToken, uint qTokenAmount) external returns (uint);

    function redeemUnderlying(address qToken, uint underlyingAmount) external returns (uint);

    function borrow(address qToken, uint amount) external;

    function repayBorrow(address qToken, uint amount) external payable;

    function repayBorrowBehalf(
        address qToken,
        address borrower,
        uint amount
    ) external payable;

    function liquidateBorrow(
        address qTokenBorrowed,
        address qTokenCollateral,
        address borrower,
        uint amount
    ) external payable;
}
