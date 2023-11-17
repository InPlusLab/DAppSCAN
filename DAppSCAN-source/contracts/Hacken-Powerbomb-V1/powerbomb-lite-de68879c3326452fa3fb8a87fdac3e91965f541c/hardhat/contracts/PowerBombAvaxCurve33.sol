// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./PowerBombAvaxCurve.sol";

contract PowerBombAvaxCurve33 is PowerBombAvaxCurve {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IWAVAX;

    function initialize(
        IPool _pool, IGauge _gauge,
        IERC20Upgradeable _rewardToken
    ) external initializer {
        __Ownable_init();

        pool = _pool;
        gauge = _gauge;
        lpToken = IERC20Upgradeable(pool.lp_token());

        yieldFeePerc = 500;
        slippagePerc = 50;
        treasury = owner();
        rewardToken = _rewardToken;
        tvlMaxLimit = 5000000e6;

        USDT.safeApprove(address(pool), type(uint).max);
        USDC.safeApprove(address(pool), type(uint).max);
        DAI.safeApprove(address(pool), type(uint).max);
        lpToken.safeApprove(address(pool), type(uint).max);
        lpToken.safeApprove(address(gauge), type(uint).max);
        WAVAX.safeApprove(address(router), type(uint).max);
        CRV.safeApprove(address(router), type(uint).max);
    }

    function _harvest(bool isDeposit) internal override {
        // Collect CRV and WAVAX from Curve
        gauge.claim_rewards();
        uint currentPool = gauge.balanceOf(address(this));

        uint WAVAXAmt = WAVAX.balanceOf(address(this));
        uint minSwapAmt = msg.sender == bot ? 50e16 : 25e16; // 0.5 : 0.25 WAVAX
        if (WAVAXAmt > minSwapAmt) {
            // Swap CRV to WAVAX
            uint CRVAmt = CRV.balanceOf(address(this));
            if (CRVAmt > 1e18) WAVAXAmt += swap2(address(CRV), address(WAVAX), CRVAmt);

            // Refund AVAX if user deposit and trigger harvest swap & refund bot
            if (msg.sender == bot || isDeposit) {
                uint amountRefund = msg.sender == bot ? 2e16 : 1e16; // 0.02 : 0.01 WAVAX
                WAVAXAmt -= amountRefund;
                WAVAX.withdraw(amountRefund);
                (bool success,) = tx.origin.call{value: address(this).balance}("");
                require(success, "AVAX transfer failed");
            }

            // Swap WAVAX to reward token
            uint rewardTokenAmt;
            rewardTokenAmt = swap2(address(WAVAX), address(rewardToken), WAVAXAmt);

            // Calculate fee
            uint fee = rewardTokenAmt * yieldFeePerc / 10000;
            rewardTokenAmt -= fee;

            // Update accRewardPerlpToken
            accRewardPerlpToken += (rewardTokenAmt * 1e36 / currentPool);

            // Transfer out fee
            rewardToken.safeTransfer(treasury, fee);

            emit Harvest(WAVAXAmt, rewardTokenAmt, fee);
        }
    }

    function claimReward(address account) public override {
        _harvest(false);

        User storage user = userInfo[account];
        if (user.lpTokenBalance > 0) {
            // Calculate user reward
            uint rewardTokenAmt = (user.lpTokenBalance * accRewardPerlpToken / 1e36) - user.rewardStartAt;
            if (rewardTokenAmt > 0) {
                user.rewardStartAt += rewardTokenAmt;

                // Transfer rewardToken to user
                rewardToken.safeTransfer(account, rewardTokenAmt);
                userAccReward[account] += rewardTokenAmt;

                emit ClaimReward(account, 0, rewardTokenAmt);
            }
        }
    }
}
