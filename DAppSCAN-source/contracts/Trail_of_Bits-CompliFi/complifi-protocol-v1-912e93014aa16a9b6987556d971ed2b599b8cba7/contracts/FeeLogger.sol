// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./libs/@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

contract FeeLogger is OwnableUpgradeSafe {
    function log(
        address _liquidityProvider,
        address _collateral,
        uint256 _protocolFee,
        address _author
    ) external {
        // timestamp
    }

    function initialize() external initializer {
        __Ownable_init();
    }

    uint256[50] private __gap;
}
