pragma solidity 0.8.6;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hegic
 * Copyright (C) 2021 Hegic Protocol
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

import "./Interfaces/IOptionsManager.sol";
import "./Interfaces/Interfaces.sol";

/**
 * @author 0mllwntrmt3
 * @title Hegic Protocol V8888 Exerciser Contract
 * @notice The contract that allows to automatically exercise options half an hour before expiration
 **/
contract Exerciser {
    IOptionsManager immutable optionsManager;

    constructor(IOptionsManager manager) {
        optionsManager = manager;
    }

    function exercise(uint256 optionId) external {
        IHegicPool pool = IHegicPool(optionsManager.tokenPool(optionId));
        (, , , , uint256 expired, ) = pool.options(optionId);
        require(
            block.timestamp > expired - 30 minutes,
            "Facade Error: Automatically exercise for this option is not available yet"
        );
        pool.exercise(optionId);
    }
}
