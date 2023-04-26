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
import "./interfaces/IQubitLocker.sol";

contract QubitDevReservoir is WhitelistUpgradeable {
    using SafeMath for uint;
    using SafeToken for address;

    /* ========== CONSTANT VARIABLES ========== */

    address internal constant QBT = 0x17B7163cf1Dbd286E262ddc68b553D899B93f526;

    /* ========== STATE VARIABLES ========== */

    address public receiver;
    IQubitLocker public qubitLocker;

    uint public startAt;
    uint public ratePerSec;
    uint public dripped;

    /* ========== INITIALIZER ========== */

    function initialize(
        address _receiver,
        uint _ratePerSec,
        uint _startAt
    ) external initializer {
        __WhitelistUpgradeable_init();

        require(_receiver != address(0), "QubitDevReservoir: invalid receiver");
        require(_ratePerSec > 0, "QubitDevReservoir: invalid rate");

        receiver = _receiver;
        ratePerSec = _ratePerSec;
        startAt = _startAt;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setLocker(address _qubitLocker) external onlyOwner {
        require(_qubitLocker != address(0), "QubitDevReservoir: invalid locker address");
        qubitLocker = IQubitLocker(_qubitLocker);
        IBEP20(QBT).approve(_qubitLocker, uint(-1));
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
        return (startAt, ratePerSec, dripped);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function drip() public onlyOwner returns (uint) {
        require(block.timestamp >= startAt, "QubitDevReservoir: not started");

        uint balance = IBEP20(QBT).balanceOf(address(this));
        uint totalDrip = ratePerSec.mul(block.timestamp.sub(startAt));
        uint amountToDrip = Math.min(balance, totalDrip.sub(dripped));
        dripped = dripped.add(amountToDrip);
        QBT.safeTransfer(receiver, amountToDrip);
        return amountToDrip;
    }

    function dripToLocker() public onlyOwner returns (uint) {
        require(address(qubitLocker) != address(0), "QubitDevReservoir: no locker assigned");
        require(block.timestamp >= startAt, "QubitDevReservoir: not started");
        uint balance = IBEP20(QBT).balanceOf(address(this));
        uint totalDrip = ratePerSec.mul(block.timestamp.sub(startAt));
        uint amountToDrip = Math.min(balance, totalDrip.sub(dripped));
        dripped = dripped.add(amountToDrip);

        if (qubitLocker.expiryOf(receiver) > block.timestamp) {
            qubitLocker.depositBehalf(receiver, amountToDrip, 0);
            return amountToDrip;
        } else {
            qubitLocker.depositBehalf(receiver, amountToDrip, block.timestamp + 365 days * 2);
            return amountToDrip;
        }
    }

    function setStartAt(uint _startAt) public onlyOwner {
        require(startAt <= _startAt, "QubitDevReservoir: invalid startAt");
        startAt = _startAt;
    }
}
