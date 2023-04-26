// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

contract FeeLoggerProxy is TransparentUpgradeableProxy {
    constructor(address _implementation, address _admin)
        public
        TransparentUpgradeableProxy(_implementation, _admin, "")
    {}
}
