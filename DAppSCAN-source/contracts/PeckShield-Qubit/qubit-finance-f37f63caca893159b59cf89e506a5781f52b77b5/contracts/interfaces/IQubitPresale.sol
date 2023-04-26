// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

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

interface IQubitPresale {
    struct PresaleData {
        uint startTime;
        uint endTime;
        uint userLpAmount;
        uint totalLpAmount;
        bool claimedOf;
        uint refundLpAmount;
        uint qbtBnbLpAmount;
    }

    function lpPriceAtArchive() external view returns (uint);

    function qbtBnbLpAmount() external view returns (uint);

    function allocationOf(address _user) external view returns (uint);

    function refundOf(address _user) external view returns (uint);

    function accountListLength() external view returns (uint);

    function setQubitBnbLocker(address _qubitBnbLocker) external;

    function setPresaleAmountUSD(uint _limitAmount) external;

    function setPeriod(uint _start, uint _end) external;

    function setQbtAmount(uint _qbtAmount) external;

    function deposit(uint _amount) external;

    function archive() external returns (uint bunnyAmount, uint wbnbAmount);

    function distribute(uint distributeThreshold) external;

    function sweep(uint _lpAmount, uint _offerAmount) external;
}
