// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IProxyVault {

    enum VaultType{
        Erc20Baic,
        UniV3
    }

    function initialize(address _owner, address _stakingAddress, address _stakingToken, address _rewardsAddress) external;
}