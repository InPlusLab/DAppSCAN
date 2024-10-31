// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./BaseGovernanceModule.sol";
import "../utils/BaseRewards.sol";


contract GovernanceRewards is BaseGovernanceModule, BaseRewards {
    using SafeMath for uint256;

    // solhint-disable-next-line no-empty-blocks
    constructor(IERC20 _gift, address _mothership) public BaseGovernanceModule(_mothership) BaseRewards(_gift) {}

    function _notifyStakeChanged(address account, uint256 newBalance) internal override updateReward(account) {
        _set(account, newBalance);
    }
}
