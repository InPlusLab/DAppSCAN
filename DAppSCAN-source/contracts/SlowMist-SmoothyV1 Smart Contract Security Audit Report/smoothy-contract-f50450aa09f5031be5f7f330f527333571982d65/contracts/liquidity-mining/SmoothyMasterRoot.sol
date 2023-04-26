// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../UpgradeableOwnableProxy.sol";


contract SmoothyMasterRoot is UpgradeableOwnableProxy {

    constructor(address implementation)
        public
        UpgradeableOwnableProxy(implementation, "")
    { }
}
