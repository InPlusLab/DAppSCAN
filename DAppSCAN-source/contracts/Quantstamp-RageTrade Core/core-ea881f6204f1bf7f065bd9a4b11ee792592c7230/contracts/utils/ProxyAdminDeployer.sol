// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { ProxyAdmin } from '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

abstract contract ProxyAdminDeployer {
    ProxyAdmin public proxyAdmin;

    function _deployProxyAdmin() internal returns (ProxyAdmin) {
        return new ProxyAdmin();
    }
}
