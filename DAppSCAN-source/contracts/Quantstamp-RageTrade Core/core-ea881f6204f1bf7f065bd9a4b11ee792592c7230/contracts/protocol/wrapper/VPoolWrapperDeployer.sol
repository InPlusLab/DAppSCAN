// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { TransparentUpgradeableProxy } from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import { IVPoolWrapper } from '../../interfaces/IVPoolWrapper.sol';

import { Governable } from '../../utils/Governable.sol';
import { ClearingHouseDeployer } from '../clearinghouse/ClearingHouseDeployer.sol';

abstract contract VPoolWrapperDeployer is Governable, ClearingHouseDeployer {
    address public vPoolWrapperLogicAddress;

    error IllegalAddress(address addr);

    constructor(address _vPoolWrapperLogicAddress) {
        vPoolWrapperLogicAddress = _vPoolWrapperLogicAddress;
    }

    /// @notice Admin method to set latest implementation logic for VPoolWrapper
    /// @param _vPoolWrapperLogicAddress: new logic address
    /// @dev When a new vPoolWrapperLogic is deployed, make sure that the initialize method is called.
    function setVPoolWrapperLogicAddress(address _vPoolWrapperLogicAddress) external onlyGovernance {
        if (_vPoolWrapperLogicAddress == address(0)) {
            revert IllegalAddress(address(0));
        }

        vPoolWrapperLogicAddress = _vPoolWrapperLogicAddress;
    }

    function _deployProxyForVPoolWrapperAndInitialize(IVPoolWrapper.InitializeVPoolWrapperParams memory params)
        internal
        returns (IVPoolWrapper vPoolWrapper)
    {
        return
            IVPoolWrapper(
                address(
                    new TransparentUpgradeableProxy(
                        address(vPoolWrapperLogicAddress),
                        address(proxyAdmin),
                        abi.encodeCall(IVPoolWrapper.initialize, (params))
                    )
                )
            );
    }
}
