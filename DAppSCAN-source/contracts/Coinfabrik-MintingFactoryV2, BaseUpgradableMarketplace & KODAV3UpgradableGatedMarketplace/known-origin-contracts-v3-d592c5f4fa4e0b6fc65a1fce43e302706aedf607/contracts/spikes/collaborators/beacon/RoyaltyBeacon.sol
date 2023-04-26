// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract RoyaltyBeacon is UpgradeableBeacon {

    constructor(address _address) UpgradeableBeacon(_address) {}

}
