// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

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
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "./library/WhitelistUpgradeable.sol";
import "./library/SafeToken.sol";

contract QubitReservoir is WhitelistUpgradeable {
    using SafeMath for uint;
    using SafeToken for address;

    /* ========== CONSTANT VARIABLES ========== */

    address private constant QBT = 0x17B7163cf1Dbd286E262ddc68b553D899B93f526;

    /* ========== STATE VARIABLES ========== */

    address public receiver;

    uint public startAt;
    uint public ratePerSec;
    uint public ratePerSec2;
    uint public ratePerSec3;
    uint public dripped;

    /* ========== INITIALIZER ========== */

    function initialize(
        address _receiver,
        uint _ratePerSec,
        uint _ratePerSec2,
        uint _ratePerSec3,
        uint _startAt
    ) external initializer {
        __WhitelistUpgradeable_init();

        require(_receiver != address(0), "QubitReservoir: invalid receiver");
        require(_ratePerSec > 0, "QubitReservoir: invalid rate");

        receiver = _receiver;
        ratePerSec = _ratePerSec;
        ratePerSec2 = _ratePerSec2;
        ratePerSec3 = _ratePerSec3;
        startAt = _startAt;
    }

    /* ========== VIEWS ========== */

    function getDripInfo()
        external
        view
        returns (
            uint,
            uint,
            uint
        )
    {
        if (block.timestamp < startAt || block.timestamp.sub(startAt) <= 30 days) {
            return (startAt, ratePerSec, dripped);
        } else if (30 days < block.timestamp.sub(startAt) && block.timestamp.sub(startAt) <= 60 days) {
            return (startAt, ratePerSec2, dripped);
        } else {
            return (startAt, ratePerSec3, dripped);
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function drip() public onlyOwner returns (uint) {
        require(block.timestamp >= startAt, "QubitReservoir: not started");

        uint balance = IBEP20(QBT).balanceOf(address(this));
        uint totalDrip;
        if (block.timestamp.sub(startAt) <= 30 days) {
            totalDrip = ratePerSec.mul(block.timestamp.sub(startAt));
        } else if (block.timestamp.sub(startAt) <= 60 days) {
            totalDrip = ratePerSec.mul(30 days);
            totalDrip = totalDrip.add(ratePerSec2.mul(block.timestamp.sub(startAt + 30 days)));
        } else {
            totalDrip = ratePerSec.mul(30 days);
            totalDrip = totalDrip.add(ratePerSec2.mul(30 days));
            totalDrip = totalDrip.add(ratePerSec3.mul(block.timestamp.sub(startAt + 60 days)));
        }

        uint amountToDrip = Math.min(balance, totalDrip.sub(dripped));
        dripped = dripped.add(amountToDrip);
        QBT.safeTransfer(receiver, amountToDrip);
        return amountToDrip;
    }

    function setStartAt(uint _startAt) public onlyOwner {
        require(startAt <= _startAt, "QubitReservoir: invalid startAt");
        startAt = _startAt;
    }
}
