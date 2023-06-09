/*

  Copyright 2019 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity ^0.5.9;
pragma experimental ABIEncoderV2;

import "./interfaces/IStaking.sol";
import "./fees/MixinExchangeManager.sol";
import "./stake/MixinZrxVault.sol";
import "./staking_pools/MixinStakingPoolRewardVault.sol";
import "./sys/MixinScheduler.sol";
import "./stake/MixinStakeBalances.sol";
import "./stake/MixinStake.sol";
import "./staking_pools/MixinStakingPool.sol";
import "./fees/MixinExchangeFees.sol";
import "./staking_pools/MixinStakingPoolRewards.sol";


contract Staking is
    IStaking,
    IStakingEvents,
    MixinDeploymentConstants,
    Ownable,
    MixinConstants,
    MixinStorage,
    MixinZrxVault,
    MixinExchangeManager,
    MixinScheduler,
    MixinStakingPoolRewardVault,
    MixinStakeStorage,
    MixinStakeBalances,
    MixinStakingPoolRewards,
    MixinStake,
    MixinStakingPool,
    MixinExchangeFees
{
    // this contract can receive ETH
    // solhint-disable no-empty-blocks
    function ()
        external
        payable
    {}
}
