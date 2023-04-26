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

import "../Interfaces/IOptionsManager.sol";

interface IHegicStakeAndCover {
    event Provided(address indexed by, uint256 hAmount, uint256 tokenAmount);
    event Withdrawn(
        address indexed by,
        address indexed hegicDestination,
        uint256 hAmount,
        uint256 tokenAmount
    );

    function availableBalance() external view returns (uint256);

    function payOut(uint256 amount) external;
}
