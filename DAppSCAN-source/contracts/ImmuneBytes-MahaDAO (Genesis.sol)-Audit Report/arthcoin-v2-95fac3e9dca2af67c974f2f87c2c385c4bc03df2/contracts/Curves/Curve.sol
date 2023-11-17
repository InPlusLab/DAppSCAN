// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from '../access/Ownable.sol';
import {ICurve} from './ICurve.sol';

abstract contract Curve is ICurve, Ownable {
    /// @notice Minimum X (e.g Collateral/Supply).
    uint256 public override minX;

    /// @notice Maximum X (e.g Collateral/Supply).
    uint256 public override maxX;

    /// @notice Minimum Y (e.g Discount/Price).
    uint256 public override minY;

    /// @notice Maximum Y (e.g Discount/Price).
    uint256 public override maxY;

    /// @notice Fixed Y(Price in some graphs) in case needed.
    uint256 public override fixedY;

    event MinXChanged(uint256 old, uint256 latest);

    event MaxXChanged(uint256 old, uint256 latest);

    event MinYChanged(uint256 old, uint256 latest);

    event MaxYChanged(uint256 old, uint256 latest);

    event FixedYChanged(uint256 old, uint256 latest);

    function setMinX(uint256 x) public virtual onlyOwner {
        uint256 oldMinX = minX;
        minX = x;
        emit MinXChanged(oldMinX, minX);
    }

    function setMaxX(uint256 x) public virtual onlyOwner {
        uint256 oldMaxX = maxX;
        maxX = x;
        emit MaxXChanged(oldMaxX, maxX);
    }

    function setFixedY(uint256 y) public virtual onlyOwner {
        uint256 old = fixedY;
        fixedY = y;
        emit FixedYChanged(old, fixedY);
    }

    function setMinY(uint256 y) public virtual onlyOwner {
        uint256 oldMinY = minY;
        minY = y;
        emit MinYChanged(oldMinY, minY);
    }

    function setMaxY(uint256 y) public virtual onlyOwner {
        uint256 oldMaxY = maxY;
        maxY = y;
       emit MaxYChanged(oldMaxY, maxY);
    }

    function getY(uint256 x) external view virtual override returns (uint256);
}
