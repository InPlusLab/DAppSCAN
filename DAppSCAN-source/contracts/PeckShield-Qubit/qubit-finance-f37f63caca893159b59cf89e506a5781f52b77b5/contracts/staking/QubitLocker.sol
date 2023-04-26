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
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../interfaces/IQubitLocker.sol";
import "../library/WhitelistUpgradeable.sol";
import "../library/SafeToken.sol";

contract QubitLocker is IQubitLocker, WhitelistUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint;
    using SafeToken for address;

    /* ========== CONSTANTS ============= */

    address public constant QBT = 0x17B7163cf1Dbd286E262ddc68b553D899B93f526;

    uint public constant LOCK_UNIT_BASE = 7 days;
    uint public constant LOCK_UNIT_MAX = 2 * 365 days;

    /* ========== STATE VARIABLES ========== */

    mapping(address => uint) public balances;
    mapping(address => uint) public expires;

    uint public override totalBalance;

    uint private _lastTotalScore;
    uint private _lastSlope;
    uint private _lastTimestamp;
    mapping(uint => uint) private _slopeChanges;

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __WhitelistUpgradeable_init();
        __ReentrancyGuard_init();
        _lastTimestamp = block.timestamp;
    }

    /* ========== VIEWS ========== */

    function balanceOf(address account) external view override returns (uint) {
        return balances[account];
    }

    function expiryOf(address account) external view override returns (uint) {
        return expires[account];
    }

    function availableOf(address account) external view override returns (uint) {
        return expires[account] < block.timestamp ? balances[account] : 0;
    }

    function balanceExpiryOf(address account) external view override returns (uint balance, uint expiry) {
        return (balances[account], expires[account]);
    }

    function totalScore() public view override returns (uint score, uint slope) {
        score = _lastTotalScore;
        slope = _lastSlope;

        uint prevTimestamp = _lastTimestamp;
        uint nextTimestamp = truncateExpiry(_lastTimestamp).add(LOCK_UNIT_BASE);
        while (nextTimestamp < block.timestamp) {
            uint deltaScore = nextTimestamp.sub(prevTimestamp).mul(slope);
            score = score < deltaScore ? 0 : score.sub(deltaScore);
            slope = slope.sub(_slopeChanges[nextTimestamp]);

            prevTimestamp = nextTimestamp;
            nextTimestamp = nextTimestamp.add(LOCK_UNIT_BASE);
        }

        uint deltaScore = block.timestamp > prevTimestamp ? block.timestamp.sub(prevTimestamp).mul(slope) : 0;
        score = score > deltaScore ? score.sub(deltaScore) : 0;
    }

    /**
     * @notice Calculate time-weighted balance of account
     * @param account Account of which the balance will be calculated
     */
    function scoreOf(address account) external view override returns (uint) {
        if (expires[account] < block.timestamp) return 0;
        return expires[account].sub(block.timestamp).mul(balances[account].div(LOCK_UNIT_MAX));
    }

    function truncateExpiry(uint time) public pure returns (uint) {
        return time.div(LOCK_UNIT_BASE).mul(LOCK_UNIT_BASE);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function deposit(uint amount, uint expiry) external override nonReentrant {
        require(amount > 0, "QubitLocker: invalid amount");

        expiry = balances[msg.sender] == 0 ? truncateExpiry(expiry) : expires[msg.sender];
        require(block.timestamp < expiry && expiry <= block.timestamp + LOCK_UNIT_MAX, "QubitLocker: invalid expiry");

        _slopeChanges[expiry] = _slopeChanges[expiry].add(amount.div(LOCK_UNIT_MAX));
        _updateTotalScore(amount, expiry);

        QBT.safeTransferFrom(msg.sender, address(this), amount);
        totalBalance = totalBalance.add(amount);

        balances[msg.sender] = balances[msg.sender].add(amount);
        expires[msg.sender] = expiry;
    }

    function extendLock(uint nextExpiry) external override nonReentrant {
        uint amount = balances[msg.sender];
        require(amount > 0, "QubitLocker: zero balance");

        uint prevExpiry = expires[msg.sender];
        nextExpiry = truncateExpiry(nextExpiry);
        require(
            Math.max(prevExpiry, block.timestamp) < nextExpiry && nextExpiry <= block.timestamp + LOCK_UNIT_MAX,
            "QubitLocker: invalid expiry time"
        );

        uint slopeChange = (_slopeChanges[prevExpiry] < amount.div(LOCK_UNIT_MAX))
            ? _slopeChanges[prevExpiry]
            : amount.div(LOCK_UNIT_MAX);
        _slopeChanges[prevExpiry] = _slopeChanges[prevExpiry].sub(slopeChange);
        _slopeChanges[nextExpiry] = _slopeChanges[nextExpiry].add(slopeChange);
        _updateTotalScoreExtendingLock(amount, prevExpiry, nextExpiry);
        expires[msg.sender] = nextExpiry;
    }

    /**
     * @notice Withdraw all tokens for `msg.sender`
     * @dev Only possible if the lock has expired
     */
    function withdraw() external override nonReentrant {
        require(balances[msg.sender] > 0 && block.timestamp >= expires[msg.sender], "QubitLocker: invalid state");
        _updateTotalScore(0, 0);

        uint amount = balances[msg.sender];
        totalBalance = totalBalance.sub(amount);
        delete balances[msg.sender];
        delete expires[msg.sender];
        QBT.safeTransfer(msg.sender, amount);
    }

    function depositBehalf(
        address account,
        uint amount,
        uint expiry
    ) external override onlyWhitelisted nonReentrant {
        require(amount > 0, "QubitLocker: invalid amount");

        expiry = balances[account] == 0 ? truncateExpiry(expiry) : expires[account];
        require(block.timestamp < expiry && expiry <= block.timestamp + LOCK_UNIT_MAX, "QubitLocker: invalid expiry");

        _slopeChanges[expiry] = _slopeChanges[expiry].add(amount.div(LOCK_UNIT_MAX));
        _updateTotalScore(amount, expiry);

        QBT.safeTransferFrom(msg.sender, address(this), amount);
        totalBalance = totalBalance.add(amount);

        balances[account] = balances[account].add(amount);
        expires[account] = expiry;
    }

    function withdrawBehalf(address account) external override onlyWhitelisted nonReentrant {
        require(balances[account] > 0 && block.timestamp >= expires[account], "QubitLocker: invalid state");
        _updateTotalScore(0, 0);

        uint amount = balances[account];
        totalBalance = totalBalance.sub(amount);
        delete balances[account];
        delete expires[account];
        QBT.safeTransfer(account, amount);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _updateTotalScore(uint newAmount, uint nextExpiry) private {
        (uint score, uint slope) = totalScore();

        if (newAmount > 0) {
            uint slopeChange = newAmount.div(LOCK_UNIT_MAX);
            uint newAmountDeltaScore = nextExpiry.sub(block.timestamp).mul(slopeChange);

            slope = slope.add(slopeChange);
            score = score.add(newAmountDeltaScore);
        }

        _lastTotalScore = score;
        _lastSlope = slope;
        _lastTimestamp = block.timestamp;
    }

    function _updateTotalScoreExtendingLock(
        uint amount,
        uint prevExpiry,
        uint nextExpiry
    ) private {
        (uint score, uint slope) = totalScore();

        uint deltaScore = nextExpiry.sub(prevExpiry).mul(amount.div(LOCK_UNIT_MAX));
        score = score.add(deltaScore);

        _lastTotalScore = score;
        _lastSlope = slope;
        _lastTimestamp = block.timestamp;
    }
}
