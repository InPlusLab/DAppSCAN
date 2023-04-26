// SPDX-License-Identifier: Unlicensed

pragma solidity 0.7.6;

import "./_openzeppelin/proxy/TransparentUpgradeableProxy.sol";

contract OneTokenProxy is TransparentUpgradeableProxy {

    constructor (address _logic, address admin_, bytes memory _data) 
        TransparentUpgradeableProxy(_logic, admin_, _data) {
    }
}