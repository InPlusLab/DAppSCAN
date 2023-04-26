// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { TransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import { ProxyAdminDeployer } from '../../utils/ProxyAdminDeployer.sol';

import { IClearingHouse } from '../../interfaces/IClearingHouse.sol';
import { IInsuranceFund } from '../../interfaces/IInsuranceFund.sol';

abstract contract InsuranceFundDeployer is ProxyAdminDeployer {
    function _deployProxyForInsuranceFund(address insuranceFundLogicAddress) internal returns (IInsuranceFund) {
        return
            IInsuranceFund(
                address(new TransparentUpgradeableProxy(insuranceFundLogicAddress, address(proxyAdmin), hex''))
            );
    }

    function _initializeInsuranceFund(
        IInsuranceFund insuranceFund,
        IERC20 settlementToken,
        IClearingHouse clearingHouse
    ) internal {
        insuranceFund.initialize(settlementToken, clearingHouse, 'RageTrade iSettlementToken', 'iSettlementToken');
    }
}
