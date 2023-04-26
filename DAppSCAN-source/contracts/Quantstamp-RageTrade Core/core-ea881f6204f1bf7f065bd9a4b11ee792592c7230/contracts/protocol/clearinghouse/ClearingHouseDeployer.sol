// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { TransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { ProxyAdminDeployer } from '../../utils/ProxyAdminDeployer.sol';

import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';
import { IClearingHouseSystemActions } from '../../interfaces/clearinghouse/IClearingHouseSystemActions.sol';
import { IInsuranceFund } from '../../interfaces/IInsuranceFund.sol';
import { IOracle } from '../../interfaces/IOracle.sol';
import { IVQuote } from '../../interfaces/IVQuote.sol';

/// @notice Manages deployment for ClearingHouseProxy
/// @dev ClearingHouse proxy is deployed only once
abstract contract ClearingHouseDeployer is ProxyAdminDeployer {
    struct DeployClearingHouseParams {
        address clearingHouseLogicAddress;
        IERC20 settlementToken;
        IOracle settlementTokenOracle;
        IInsuranceFund insuranceFund;
        IVQuote vQuote;
    }

    function _deployProxyForClearingHouseAndInitialize(DeployClearingHouseParams memory params)
        internal
        returns (IClearingHouse)
    {
        return
            IClearingHouse(
                address(
                    new TransparentUpgradeableProxy(
                        params.clearingHouseLogicAddress,
                        address(proxyAdmin),
                        abi.encodeCall(
                            IClearingHouseSystemActions.initialize,
                            (
                                address(this), // RageTradeFactory
                                params.settlementToken,
                                params.settlementTokenOracle,
                                params.insuranceFund,
                                params.vQuote
                            )
                        )
                    )
                )
            );
    }
}
