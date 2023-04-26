// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.10;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MockSetBooster {
    mapping(ERC20 => mapping(address => uint256)) public userBoosts;
    mapping(ERC20 => uint256) public totalBoosts;

    function setUserBoost(
        ERC20 strat,
        address user,
        uint256 boost
    ) public {
        userBoosts[strat][user] = boost;
    }

    function setTotalSupplyBoost(ERC20 strat, uint256 boost) public {
        totalBoosts[strat] = boost;
    }

    function boostedTotalSupply(ERC20 strategy)
        external
        view
        returns (uint256)
    {
        return totalBoosts[strategy];
    }

    function boostedBalanceOf(ERC20 strategy, address user)
        external
        view
        returns (uint256)
    {
        return userBoosts[strategy][user];
    }
}
