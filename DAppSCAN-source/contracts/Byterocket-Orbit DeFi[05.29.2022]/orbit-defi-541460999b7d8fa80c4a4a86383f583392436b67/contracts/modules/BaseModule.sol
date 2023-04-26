// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import '../../interfaces/IRegistry.sol';
import '../../interfaces/IPositionManager.sol';

contract BaseModule {
    IRegistry registry;

    modifier onlyWhitelistedKeeper() {
        require(
            registry.isWhitelistedKeeper(msg.sender),
            'Module::onlyWhitelistedKeeper: Only whitelisted keepers can call this function'
        );
        _;
    }

    modifier activeModule(address positionManager, uint256 tokenId) {
        (bool isActive, ) = IPositionManager(positionManager).getModuleInfo(tokenId, address(this));
        require(isActive, 'Module::activeModule: Module is inactive.');
        _;
    }

    constructor(address _registry) {
        registry = IRegistry(_registry);
    }
}
