// SPDX-License-Identifier: BSL-1.1
// Gearbox. Generalized leverage protocol that allows to take leverage and then use it across other DeFi protocols and platforms in a composable way.
// (c) Gearbox.fi, 2021
pragma solidity ^0.7.4;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {PercentageMath} from "../libraries/math/PercentageMath.sol";
import {WadRayMath} from "../libraries/math/WadRayMath.sol";
import {IInterestRateModel} from "../interfaces/IInterestRateModel.sol";
import {Constants} from "../libraries/helpers/Constants.sol";
import "hardhat/console.sol";

/// @title Linear Interest Rate Model
/// @notice Linear interest rate model, similar which Aave uses
contract LinearInterestRateModel is IInterestRateModel {
    using PercentageMath for uint256;
    using SafeMath for uint256;
    using WadRayMath for uint256;

    // Uoptimal[0;1] in Wad
    uint256 public immutable _U_Optimal_WAD;

    // 1 - Uoptimal [0;1] x10.000, percentage plus two decimals
    uint256 public immutable _U_Optimal_inverted_WAD;

    // R_base in Ray
    uint256 public immutable _R_base_RAY;

    // R_Slope1 in Ray
    uint256 public immutable _R_slope1_RAY;

    // R_Slope2 in Ray
    uint256 public immutable _R_slope2_RAY;

    /// @dev Constructor
    /// @param U_optimal Optimal U in percentage format: x10.000 - percentage plus two decimals
    /// @param R_base R_base in percentage format: x10.000 - percentage plus two decimals @param R_slope1 R_Slope1 in Ray
    /// @param R_slope1 R_Slope1 in percentage format: x10.000 - percentage plus two decimals
    /// @param R_slope2 R_Slope2 in percentage format: x10.000 - percentage plus two decimals
    constructor(
        uint256 U_optimal,
        uint256 R_base,
        uint256 R_slope1,
        uint256 R_slope2
    ) {
        // Convert percetns to WAD
        uint256 U_optimal_WAD = WadRayMath.WAD.percentMul(U_optimal);
        _U_Optimal_WAD = U_optimal_WAD;

        // 1 - Uoptimal in WAD
        _U_Optimal_inverted_WAD = WadRayMath.WAD.sub(U_optimal_WAD);

        _R_base_RAY = WadRayMath.RAY.percentMul(R_base);
        _R_slope1_RAY = WadRayMath.RAY.percentMul(R_slope1);
        _R_slope2_RAY = WadRayMath.RAY.percentMul(R_slope2);
    }

    /// @dev Calculated borrow rate based on expectedLiquidity and availableLiquidity
    /// @param expectedLiquidity Expected liquidity in the pool
    /// @param availableLiquidity Available liquidity in the pool
    function calcBorrowRate(
        uint256 expectedLiquidity,
        uint256 availableLiquidity
    ) external view override returns (uint256) {
        // Protection from direct sending tokens on PoolService account
        //    T:[LR-5]                     // T:[LR-6]
        if (expectedLiquidity == 0 || expectedLiquidity < availableLiquidity) {
            return _R_base_RAY;
        }

        //      expectedLiquidity - availableLiquidity
        // U = -------------------------------------
        //             expectedLiquidity

        uint256 U_WAD = (expectedLiquidity.sub(availableLiquidity))
        .mul(WadRayMath.WAD)
        .div(expectedLiquidity);

        // if U < Uoptimal:
        //
        //                                    U
        // borrowRate = Rbase + Rslope1 * ----------
        //                                 Uoptimal
        //

        if (U_WAD < _U_Optimal_WAD) {
            return
                _R_base_RAY.add(_R_slope1_RAY.mul(U_WAD).div(_U_Optimal_WAD));
        }

        // if U >= Uoptimal:
        //
        //                                           U - Uoptimal
        // borrowRate = Rbase + Rslope1 + Rslope2 * --------------
        //                                           1 - Uoptimal

        return
            _R_base_RAY.add(_R_slope1_RAY).add(
                _R_slope2_RAY.mul(U_WAD.sub(_U_Optimal_WAD)).div(
                    _U_Optimal_inverted_WAD
                )
            ); // T:[LR-1,2,3]
    }

    /// @dev Gets model parameters
    /// @param U_optimal U_optimal in percentage format: [0;10,000] - percentage plus two decimals
    /// @param R_base R_base in RAY format
    /// @param R_slope1 R_slope1 in RAY format
    /// @param R_slope2 R_slope2 in RAY format
    function getModelParameters()
        external
        view
        returns (
            uint256 U_optimal,
            uint256 R_base,
            uint256 R_slope1,
            uint256 R_slope2
        )
    {
        U_optimal = _U_Optimal_WAD.percentDiv(WadRayMath.WAD); // T:[LR-4]
        R_base = _R_base_RAY; // T:[LR-4]
        R_slope1 = _R_slope1_RAY; // T:[LR-4]
        R_slope2 = _R_slope2_RAY; // T:[LR-4]
    }
}
