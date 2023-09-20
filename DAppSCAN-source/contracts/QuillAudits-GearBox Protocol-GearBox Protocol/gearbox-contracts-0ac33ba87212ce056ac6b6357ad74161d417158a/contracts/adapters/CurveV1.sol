// SPDX-License-Identifier: MIT
// Gearbox. Generalized leverage protocol that allows to take leverage and then use it across other DeFi protocols and platforms in a composable way.
// (c) Gearbox.fi, 2021
pragma solidity ^0.7.4;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {ICreditFilter} from "../interfaces/ICreditFilter.sol";
import {ICreditManager} from "../interfaces/ICreditManager.sol";
import {ICurvePool} from "../integrations/curve/ICurvePool.sol";

import {CreditAccount} from "../credit/CreditAccount.sol";
import {CreditManager} from "../credit/CreditManager.sol";

import {Constants} from "../libraries/helpers/Constants.sol";
import {Errors} from "../libraries/helpers/Errors.sol";

import "hardhat/console.sol";

/// @title CurveV1 adapter
contract CurveV1Adapter is ICurvePool {
    using SafeMath for uint256;

    // Default swap contracts - uses for automatic close / liquidation process
    ICurvePool public curvePool; //
    ICreditManager public creditManager;
    ICreditFilter public creditFilter;

    /// @dev Constructor
    /// @param _creditManager Address Credit manager
    /// @param _curvePool Address of curve-compatible pool
    constructor(address _creditManager, address _curvePool) {
        creditManager = ICreditManager(_creditManager);
        creditFilter = ICreditFilter(creditManager.creditFilter());

        curvePool = ICurvePool(_curvePool);
    }

    function coins(uint256 i) external view override returns (address) {
        return ICurvePool(curvePool).coins(i);
    }

    /// @dev Exchanges two assets on Curve-compatible pools. Restricted for pool calls only
    /// @param i Index value for the coin to send
    /// @param j Index value of the coin to receive
    /// @param dx Amount of i being exchanged
    /// @param min_dy Minimum amount of j to receive
    // SWC-107-Reentrancy: L49 - L85
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external override {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        );

        address tokenIn = curvePool.coins(uint256(i));
        address tokenOut = curvePool.coins(uint256(j));

        creditManager.provideCreditAccountAllowance(
            creditAccount,
            address(curvePool),
            tokenIn
        ); // T:[CVA-3]

        bytes memory data = abi.encodeWithSelector(
            bytes4(0x3df02124), // "exchange(int128,int128,uint256,uint256)",
            i,
            j,
            dx,
            min_dy
        ); // T:[CVA-3]

        creditManager.executeOrder(msg.sender, address(curvePool), data); // T:[CVA-3]

        creditFilter.checkCollateralChange(
            creditAccount,
            tokenIn,
            tokenOut,
            dx,
            min_dy
        ); // T:[CVA-2]
    }

    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external override {
        revert(Errors.NOT_IMPLEMENTED);
    }

    // SWC-135-Code With No Effects: L97 - L103
    function get_dx_underlying(
        int128 i,
        int128 j,
        uint256 dy
    ) external view override returns (uint256) {
        return curvePool.get_dx_underlying(i, j, dy);
    }

    function get_dy_underlying(
        int128 i,
        int128 j,
        uint256 dx
    ) external view override returns (uint256) {
        return curvePool.get_dy_underlying(i, j, dx);
    }

    // SWC-135-Code With No Effects: L114 - L120
    function get_dx(
        int128 i,
        int128 j,
        uint256 dy
    ) external view override returns (uint256) {
        return curvePool.get_dx(i, j, dy);
    }

    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view override returns (uint256) {
        return curvePool.get_dy(i, j, dx);
    }

    function get_virtual_price() external view override returns (uint256) {
        return curvePool.get_virtual_price();
    }
}
