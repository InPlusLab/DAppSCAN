// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./ITenderFarm.sol";
import "../token/ITenderToken.sol";
import "../tenderizer/ITenderizer.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract TenderFarmFactory {
    ITenderFarm immutable farmTarget;

    constructor(ITenderFarm _farm) {
        farmTarget = _farm;
    }

    event NewTenderFarm(ITenderFarm farm, IERC20 stakeToken, ITenderToken rewardToken, ITenderizer tenderizer);

    function deploy(
        IERC20 _stakeToken,
        ITenderToken _rewardToken,
        ITenderizer _tenderizer
    ) public returns (ITenderFarm farm) {
        farm = ITenderFarm(Clones.clone(address(farmTarget)));

        require(farm.initialize(_stakeToken, _rewardToken, _tenderizer), "FAIL_INIT_TENDERFARM");

        emit NewTenderFarm(farm, _stakeToken, _rewardToken, _tenderizer);
    }
}
