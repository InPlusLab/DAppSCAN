// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../governance/BaseGovernanceModule.sol";
import "../utils/BalanceAccounting.sol";


contract GovernanceModuleMock is BaseGovernanceModule, BalanceAccounting {
    // solhint-disable-next-line no-empty-blocks
    constructor(address _mothership) public BaseGovernanceModule(_mothership) {}

    function _notifyStakeChanged(address account, uint256 newBalance) internal override {
        _set(account, newBalance);
    }
}
