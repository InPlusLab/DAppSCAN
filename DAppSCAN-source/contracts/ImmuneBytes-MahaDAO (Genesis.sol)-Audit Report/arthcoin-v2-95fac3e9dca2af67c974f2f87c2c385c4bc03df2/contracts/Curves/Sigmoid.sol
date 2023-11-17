// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Curve} from './Curve.sol';
import {Math} from '../utils/math/Math.sol';
import {SafeMath} from '../utils/math/SafeMath.sol';

contract Sigmoid is Curve {
    using SafeMath for uint256;

    /// @dev Tells whether the curve is for discount(decreasing) or price(increasing)?
    bool public isIncreasingCurve = true;

    /// @dev Slots to generate a sigmoid curve.
    uint256[] internal _slots;

    constructor(
        uint256 _minX,
        uint256 _maxX,
        uint256 _minY,
        uint256 _maxY,
        bool increasingCurve,
        uint256[] memory slots
    ) {
        minX = _minX; // I.E 0%.
        maxX = _maxX; // I.E 100%.
        minY = _minY; // I.E 0.00669%.
        maxY = _maxY; // I.E 0.5%.

        isIncreasingCurve = increasingCurve;

        _slots = slots;
    }

    function setMinX(uint256 x) public override onlyOwner {
        super.setMinX(x);
    }

    function setMaxX(uint256 x) public override onlyOwner {
        super.setMaxX(x);
    }

    function setMinY(uint256 y) public override onlyOwner {
        super.setMinY(y);
    }

    function setFixedY(uint256 y) public override onlyOwner {
        super.setFixedY(y);
    }

    function setMaxY(uint256 y) public override onlyOwner {
        super.setMaxY(y);
    }

    function getY(uint256 x) public view virtual override returns (uint256) {
        // If price(increasing curve) then should return minY(min price in beginning) in starting.
        // else should return maxY(max discount in beginning) in start.
        if (x <= minX) return isIncreasingCurve ? minY : maxY;
        if (x >= maxX) return isIncreasingCurve ? maxY : minY;

        uint256 slotWidth = maxX.sub(minX).div(_slots.length);
        uint256 xa = x.sub(minX).div(slotWidth);
        uint256 xb = Math.min(xa.add(1), _slots.length.sub(1));

        uint256 slope = _slots[xa].sub(_slots[xb]).mul(1e18).div(slotWidth);
        uint256 wy = _slots[xa].add(slope.mul(slotWidth.mul(xa)).div(1e18));

        uint256 percentage = 0;
        if (wy > slope.mul(x).div(1e18)) {
            percentage = wy.sub(slope.mul(x).div(1e18));
        } else {
            percentage = slope.mul(x).div(1e18).sub(wy);
        }

        return minY.add(maxY.sub(minY).mul(percentage).div(1e18));
    }
}
