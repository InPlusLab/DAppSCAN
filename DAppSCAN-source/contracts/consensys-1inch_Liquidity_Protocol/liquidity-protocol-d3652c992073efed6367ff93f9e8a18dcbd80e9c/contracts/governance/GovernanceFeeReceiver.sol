// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../utils/Converter.sol";
import "../utils/RewardDistributionRecipient.sol";


contract GovernanceFeeReceiver is Converter {
    RewardDistributionRecipient public immutable rewards;

    constructor(IERC20 _inchToken, RewardDistributionRecipient _rewards, IMooniswapFactory _mooniswapFactory)
        public Converter(_inchToken, _mooniswapFactory)
    {
        rewards = _rewards;
    }

    function unwrapLPTokens(Mooniswap mooniswap) external validSpread(mooniswap) {
        mooniswap.withdraw(mooniswap.balanceOf(address(this)), new uint256[](0));
    }

    function swap(IERC20[] memory path) external validPath(path) {
        (uint256 amount,) = _maxAmountForSwap(path, path[0].uniBalanceOf(address(this)));
        uint256 result = _swap(path, amount, payable(address(rewards)));
        rewards.notifyRewardAmount(result);
    }
}
