pragma solidity ^0.8.0;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Buffer
 * Copyright (C) 2020 Buffer Protocol
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import "../Interfaces/Interfaces.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @author Heisenberg
 * @title Buffer BNB Liquidity Pool
 * @notice Accumulates liquidity in BNB from LPs and distributes P&L in BNB
 */
contract BufferBNBPool is
    AccessControl,
    ERC20("Buffer BNB LP Token", "rBFR-BNB"),
    IBNBLiquidityPool
{
    uint256 public constant ACCURACY = 1e3;
    uint256 public constant INITIAL_RATE = 1e3;
    uint256 public lockupPeriod = 2 weeks;
    uint256 public lockedAmount;
    uint256 public lockedPremium;
    uint256 public referralRewardPercentage = 500; // 0.5%

    mapping(address => uint256) public lastProvideTimestamp;
    mapping(address => bool) public _revertTransfersInLockUpPeriod;
    // LockedLiquidity[] public lockedLiquidity;
    mapping(address => LockedLiquidity[]) public lockedLiquidity;

    bytes32 public constant OPTION_ISSUER_ROLE =
        keccak256("OPTION_ISSUER_ROLE");

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Used for ...
     */
    function revertTransfersInLockUpPeriod(bool value) external {
        _revertTransfersInLockUpPeriod[msg.sender] = value;
    }

    /*
     * @nonce A provider supplies BNB to the pool and receives rBFR-BNB tokens
     * @param referrer Address of referred by.
     * @param minMint Minimum amount of tokens that should be received by a provider.
                      Calling the provide function will require the minimum amount of tokens to be minted.
                      The actual amount that will be minted could vary but can only be higher (not lower) than the minimum value.
     * @return mint Amount of tokens to be received
     */
    function provide(uint256 minMint , address referrer) external payable returns (uint256 mint) {
        lastProvideTimestamp[msg.sender] = block.timestamp;
        uint256 supply = totalSupply();
        uint256 balance = totalBalance();

        uint256 amount = msg.value;

        if(referrer != address(0) && referrer != msg.sender){
            uint256 referralReward = ((msg.value * referralRewardPercentage)/ACCURACY)/100;
            amount = msg.value - referralReward;      

            if (referralReward > 0){
                payable(referrer).transfer(referralReward);
            }                  
        }

        if (supply > 0 && balance > 0)
            mint = (amount * supply) / (balance - amount);
        else mint = amount * INITIAL_RATE;

        require(mint >= minMint, "Pool: Mint limit is too large");
        require(mint > 0, "Pool: Amount is too small");

        _mint(msg.sender, mint);

        emit Provide(msg.sender, amount, mint);
    }

    /*
     * @nonce Provider burns rBFR-BNB and receives BNB from the pool
     * @param amount Amount of BNB to receive
     * @return burn Amount of tokens to be burnt
     */
    function withdraw(uint256 amount, uint256 maxBurn)
        external
        returns (uint256 burn)
    {
        require(
            lastProvideTimestamp[msg.sender] + lockupPeriod <= block.timestamp,
            "Pool: Withdrawal is locked up"
        );
        require(
            amount <= availableBalance(),
            "Pool Error: Not enough funds on the pool contract. Please lower the amount."
        );

        burn = divCeil((amount * totalSupply()), totalBalance());

        require(burn <= maxBurn, "Pool: Burn limit is too small");
        require(burn <= balanceOf(msg.sender), "Pool: Amount is too large");
        require(burn > 0, "Pool: Amount is too small");

        _burn(msg.sender, burn);
        emit Withdraw(msg.sender, amount, burn);

        payable(msg.sender).transfer(amount);
    }

    /*
     * @nonce calls by BufferCallOptions to lock the funds
     * @param amount Amount of funds that should be locked in an option
     */
    function lock(uint256 id, uint256 amount) external payable override {
        require(
            hasRole(OPTION_ISSUER_ROLE, msg.sender),
            "msg.sender is not allowed to excute the option contract"
        );
        require(id == lockedLiquidity[msg.sender].length, "Wrong id");
        require(totalBalance() >= msg.value, "Insufficient balance");
        require(
            (lockedAmount + amount) <= ((totalBalance() - msg.value) * 8) / 10,
            "Pool Error: Amount is too large."
        );

        lockedLiquidity[msg.sender].push(LockedLiquidity(amount, msg.value, true));
        lockedPremium = lockedPremium + msg.value;
        lockedAmount = lockedAmount + amount;
    }

    /*
     * @nonce calls by BufferOptions to unlock the funds
     * @param id Id of LockedLiquidity that should be unlocked
     */
    function unlock(uint256 id) external override {
        require(
            hasRole(OPTION_ISSUER_ROLE, msg.sender),
            "msg.sender is not allowed to excute the option contract"
        );
        LockedLiquidity storage ll = lockedLiquidity[msg.sender][id];
        require(ll.locked, "LockedLiquidity with such id has already unlocked");
        ll.locked = false;

        lockedPremium = lockedPremium - ll.premium;
        lockedAmount = lockedAmount - ll.amount;

        emit Profit(id, ll.premium);
    }

    /*
     * @nonce calls by BufferCallOptions to send funds to liquidity providers after an option's expiration
     * @param to Provider
     * @param amount Funds that should be sent
     */
    function send(
        uint256 id,
        address payable to,
        uint256 amount
    ) external override {
        require(
            hasRole(OPTION_ISSUER_ROLE, msg.sender),
            "msg.sender is not allowed to excute the option contract"
        );
        LockedLiquidity storage ll = lockedLiquidity[msg.sender][id];
        require(ll.locked, "LockedLiquidity with such id has already unlocked");
        require(to != address(0));

        ll.locked = false;
        lockedPremium = lockedPremium - ll.premium;
        lockedAmount = lockedAmount - ll.amount;

        uint256 transferAmount = amount > ll.amount ? ll.amount : amount;
        to.transfer(transferAmount);

        if (transferAmount <= ll.premium)
            emit Profit(id, ll.premium - transferAmount);
        else emit Loss(id, transferAmount - ll.premium);
    }

    /*
     * @nonce Returns provider's share in BNB
     * @param account Provider's address
     * @return Provider's share in BNB
     */
    function shareOf(address account) external view returns (uint256 share) {
        if (totalSupply() > 0)
            share = (totalBalance() * balanceOf(account)) / totalSupply();
        else share = 0;
    }

    /*
     * @nonce Returns the amount of BNB available for withdrawals
     * @return balance Unlocked amount
     */
    function availableBalance() public view returns (uint256 balance) {
        return totalBalance() - lockedAmount;
    }

    /*
     * @nonce Returns the total balance of BNB provided to the pool
     * @return balance Pool balance
     */
    function totalBalance() public view override returns (uint256 balance) {
        return address(this).balance - lockedPremium;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal override {
        if (
            lastProvideTimestamp[from] + lockupPeriod > block.timestamp &&
            lastProvideTimestamp[from] > lastProvideTimestamp[to]
        ) {
            require(
                !_revertTransfersInLockUpPeriod[to],
                "the recipient does not accept blocked funds"
            );
            lastProvideTimestamp[to] = lastProvideTimestamp[from];
        }
    }

    /**
     * @dev calculates x*y and outputs a emulated 512bit number as l being the lower 256bit half and h the upper 256bit half.
     */
    function fullMul(uint256 x, uint256 y)
        public
        pure
        returns (uint256 l, uint256 h)
    {
        uint256 mm = mulmod(x, y, ~uint256(0));
        l = x * y;
        h = mm - l;
        if (mm < l) h -= 1;
    }

    /**
     * @dev calculates x*y/z taking care of phantom overflows.
     */
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 z
    ) public pure returns (uint256) {
        (uint256 l, uint256 h) = fullMul(x, y);
        require(h < z);
        uint256 mm = mulmod(x, y, z);
        if (mm > l) h -= 1;
        l -= mm;
        uint256 pow2 = z & (~uint256(0) - z);
        z /= pow2;
        l /= pow2;
        l += h * ((~uint256(0) - pow2) / pow2 + 1);
        uint256 r = 1;
        r *= 2 - z * r;
        r *= 2 - z * r;
        r *= 2 - z * r;
        r *= 2 - z * r;
        r *= 2 - z * r;
        r *= 2 - z * r;
        r *= 2 - z * r;
        r *= 2 - z * r;
        return l * r;
    }

    function divCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;
        if (a % b != 0) c = c + 1;
        return c;
    }
}
