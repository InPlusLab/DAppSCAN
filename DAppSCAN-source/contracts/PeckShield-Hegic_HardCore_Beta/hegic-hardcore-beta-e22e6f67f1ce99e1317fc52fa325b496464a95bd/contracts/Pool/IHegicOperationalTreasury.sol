pragma solidity 0.8.6;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hegic
 * Copyright (C) 2022 Hegic Protocol
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
 **/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Interfaces/IOptionsManager.sol";

interface IHegicOperationalTreasury {
    enum LockedLiquidityState {Unlocked, Locked}

    event Expired(uint256 indexed id);
    event Paid(uint256 indexed id, address indexed account, uint256 amount);
    event Replenished(uint256 amount);

    struct LockedLiquidity {
        LockedLiquidityState state;
        address strategy;
        uint128 amount;
        uint128 premium;
        uint32 expiration;
    }

    function manager() external view returns (IOptionsManager);

    function token() external view returns (IERC20);

    function lockLiquidityFor(
        address holder,
        uint128 amount,
        uint32 expiration
    ) external returns (uint256 optionID);

    function payOff(
        uint256 lockedLiquidityID,
        uint256 amount,
        address account
    ) external;

    function lockedByStrategy(address strategy)
        external
        view
        returns (uint256 lockedAmount);

    function totalBalance() external view returns (uint256 totalBalance);

    function benchmark() external view returns (uint256 benchmark);

    function totalLocked() external view returns (uint256 totalLocked);
}
