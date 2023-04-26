// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

/*
      ___       ___       ___       ___       ___
     /\  \     /\__\     /\  \     /\  \     /\  \
    /::\  \   /:/ _/_   /::\  \   _\:\  \    \:\  \
    \:\:\__\ /:/_/\__\ /::\:\__\ /\/::\__\   /::\__\
     \::/  / \:\/:/  / \:\::/  / \::/\/__/  /:/\/__/
     /:/  /   \::/  /   \::/  /   \:\__\    \/__/
     \/__/     \/__/     \/__/     \/__/

*
* MIT License
* ===========
*
* Copyright (c) 2021 QubitFinance
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*/

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../../interfaces/IRateModel.sol";

contract RateModelSlope is IRateModel, OwnableUpgradeable {
    using SafeMath for uint;

    uint private baseRatePerYear;
    uint private slopePerYearFirst;
    uint private slopePerYearSecond;
    uint private optimal;

    function initialize(
        uint _baseRatePerYear,
        uint _slopePerYearFirst,
        uint _slopePerYearSecond,
        uint _optimal
    ) external initializer {
        __Ownable_init();

        baseRatePerYear = _baseRatePerYear;
        slopePerYearFirst = _slopePerYearFirst;
        slopePerYearSecond = _slopePerYearSecond;
        optimal = _optimal;
    }

    function utilizationRate(
        uint cash,
        uint borrows,
        uint reserves
    ) public pure returns (uint) {
        if (reserves >= cash.add(borrows)) return 0;
        return Math.min(borrows.mul(1e18).div(cash.add(borrows).sub(reserves)), 1e18);
    }

    function getBorrowRate(
        uint cash,
        uint borrows,
        uint reserves
    ) public view override returns (uint) {
        uint utilization = utilizationRate(cash, borrows, reserves);
        if (optimal > 0 && utilization < optimal) {
            return baseRatePerYear.add(utilization.mul(slopePerYearFirst).div(optimal)).div(365 days);
        } else {
            uint ratio = utilization.sub(optimal).mul(1e18).div(uint(1e18).sub(optimal));
            return baseRatePerYear.add(slopePerYearFirst).add(ratio.mul(slopePerYearSecond).div(1e18)).div(365 days);
        }
    }

    function getSupplyRate(
        uint cash,
        uint borrows,
        uint reserves,
        uint reserveFactor
    ) public view override returns (uint) {
        uint oneMinusReserveFactor = uint(1e18).sub(reserveFactor);
        uint borrowRate = getBorrowRate(cash, borrows, reserves);
        uint rateToPool = borrowRate.mul(oneMinusReserveFactor).div(1e18);
        return utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18);
    }
}
