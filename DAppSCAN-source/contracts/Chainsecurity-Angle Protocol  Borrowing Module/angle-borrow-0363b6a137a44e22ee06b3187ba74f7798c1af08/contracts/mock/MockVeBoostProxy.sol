// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "../interfaces/governance/IVeBoostProxy.sol";

contract MockVeBoostProxy is IVeBoostProxy {
    //solhint-disable-next-line
    mapping(address => uint256) public adjusted_balance_of;

    constructor() {}

    function setBalance(address concerned, uint256 balance) external {
        adjusted_balance_of[concerned] = balance;
    }
}
