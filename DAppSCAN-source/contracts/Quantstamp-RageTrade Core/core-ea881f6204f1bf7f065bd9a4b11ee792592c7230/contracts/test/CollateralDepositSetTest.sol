// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Uint32L8ArrayLib } from '../libraries/Uint32L8Array.sol';
import { VPoolWrapperMock } from './mocks/VPoolWrapperMock.sol';

import { AddressHelper } from '../libraries/AddressHelper.sol';
import { CollateralDeposit } from '../libraries/CollateralDeposit.sol';

import { IVToken } from '../interfaces/IVToken.sol';
import { IOracle } from '../interfaces/IOracle.sol';
import { IClearingHouseStructures } from '../interfaces/clearinghouse/IClearingHouseStructures.sol';

import { AccountProtocolInfoMock } from './mocks/AccountProtocolInfoMock.sol';

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract CollateralDepositSetTest is AccountProtocolInfoMock {
    using CollateralDeposit for CollateralDeposit.Set;
    using AddressHelper for address;
    using AddressHelper for IERC20;
    using Uint32L8ArrayLib for uint32[8];

    CollateralDeposit.Set depositTokenSet;

    VPoolWrapperMock public wrapper;

    constructor(address _settlementToken) {
        wrapper = new VPoolWrapperMock();
        protocol.settlementToken = IERC20(_settlementToken);
    }

    function initVToken(address vToken) external {
        protocol.pools[vToken.truncate()].vToken = IVToken(vToken);
    }

    function init(
        IERC20 cToken,
        IOracle oracle,
        uint32 twapDuration
    ) external {
        IClearingHouseStructures.Collateral memory collateral = IClearingHouseStructures.Collateral(
            cToken,
            IClearingHouseStructures.CollateralSettings(oracle, twapDuration, true)
        );
        protocol.collaterals[collateral.token.truncate()] = collateral;
    }

    function cleanDeposits() external {
        for (uint256 i = 0; i < depositTokenSet.active.length; i++) {
            uint32 collateralId = depositTokenSet.active[i];
            if (collateralId == 0) break;

            depositTokenSet.decreaseBalance(collateralId, depositTokenSet.deposits[collateralId]);
        }
    }

    function increaseBalance(address realTokenAddress, uint256 amount) external {
        depositTokenSet.increaseBalance(realTokenAddress.truncate(), amount);
    }

    function decreaseBalance(address realTokenAddress, uint256 amount) external {
        depositTokenSet.decreaseBalance(realTokenAddress.truncate(), amount);
    }

    function getAllDepositAccountMarketValue() external view returns (int256 depositValue) {
        return depositTokenSet.marketValue(protocol);
    }

    function getBalance(address realTokenAddress) external view returns (uint256 balance) {
        return depositTokenSet.deposits[realTokenAddress.truncate()];
    }
}
