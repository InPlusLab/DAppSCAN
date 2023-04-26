// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../UpgradeableOwnableProxy.sol";


contract VotingEscrowRoot is UpgradeableOwnableProxy {

    constructor(address implementation)
        public
        UpgradeableOwnableProxy(implementation, "")
    { }
}
