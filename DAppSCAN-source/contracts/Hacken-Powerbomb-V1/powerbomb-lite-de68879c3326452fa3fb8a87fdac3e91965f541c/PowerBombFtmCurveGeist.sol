// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./PowerBombAvaxCurve.sol";

contract PowerBombFtmCurveGeist is PowerBombAvaxCurve {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable constant fUSDT = IERC20Upgradeable(0x049d68029688eAbF473097a2fC38ef61633A3C7A);
    IERC20Upgradeable constant fUSDC = IERC20Upgradeable(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);
    IERC20Upgradeable constant fDAI = IERC20Upgradeable(0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E);
    IERC20Upgradeable constant WFTM = IERC20Upgradeable(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    IERC20Upgradeable constant GEIST = IERC20Upgradeable(0xd8321AA83Fb0a4ECd6348D4577431310A6E0814d);
    IERC20Upgradeable constant fCRV = IERC20Upgradeable(0x1E4F97b9f9F913c46F1632781732927B9019C68b);
    IRouter constant spookyRouter = IRouter(0xF491e7B69E4244ad4002BC14e878a34207E38c29);

    function initialize(
        IPool _pool, IGauge _gauge,
        IERC20Upgradeable _rewardToken, address _treasury
    ) external initializer {
        __Ownable_init();

        pool = _pool;
        gauge = _gauge;
        lpToken = IERC20Upgradeable(pool.lp_token());

        yieldFeePerc = 500;
        slippagePerc = 50;
        treasury = _treasury;
        rewardToken = _rewardToken;
        tvlMaxLimit = 5000000e6;

        fUSDT.safeApprove(address(pool), type(uint).max);
        fUSDC.safeApprove(address(pool), type(uint).max);
        fDAI.safeApprove(address(pool), type(uint).max);
        lpToken.safeApprove(address(pool), type(uint).max);
        lpToken.safeApprove(address(gauge), type(uint).max);
        WFTM.safeApprove(address(spookyRouter), type(uint).max);
        fCRV.safeApprove(address(spookyRouter), type(uint).max);
        GEIST.safeApprove(address(spookyRouter), type(uint).max);
    }

    function _deposit(IERC20Upgradeable token, uint amount, address depositor, uint slippage) internal virtual override nonReentrant whenNotPaused {
        require(token == fUSDT || token == fUSDC || token == fDAI || token == lpToken, "Invalid token");
        require(amount > 0, "Invalid amount");
        require(getAllPoolInUSD() < tvlMaxLimit, "TVL max Limit reach");

        uint currentPool = gauge.balanceOf(address(this));
        if (currentPool > 0) _harvest(true);

        token.safeTransferFrom(msg.sender, address(this), amount);
        depositedBlock[depositor] = block.number;

        uint lpTokenAmt;
        if (token != lpToken) {
            uint[3] memory amounts;
            if (token == fUSDT) amounts[2] = amount;
            else if (token == fUSDC) amounts[1] = amount;
            else if (token == fDAI) amounts[0] = amount;

            if (token != fDAI) amount *= 1e12;
            uint estimatedMintAmt = amount * 1e18 / pool.get_virtual_price();
            uint minMintAmt = estimatedMintAmt - (estimatedMintAmt * slippage / 10000);

            lpTokenAmt = pool.add_liquidity(amounts, minMintAmt, true);
        } else {
            lpTokenAmt = amount;
        }

        gauge.deposit(lpTokenAmt);
        User storage user = userInfo[depositor];
        user.lpTokenBalance += lpTokenAmt;
        user.rewardStartAt += (lpTokenAmt * accRewardPerlpToken / 1e36);

        emit Deposit(address(token), amount, lpTokenAmt);
    }

    function withdraw(IERC20Upgradeable token, uint amountOutLpToken, uint slippage) external virtual override nonReentrant {
        require(token == fUSDT || token == fUSDC || token == fDAI || token == lpToken, "Invalid token");
        User storage user = userInfo[msg.sender];
        require(amountOutLpToken > 0 && user.lpTokenBalance >= amountOutLpToken, "Invalid amountOutLpToken to withdraw");
        require(depositedBlock[msg.sender] != block.number, "Not allow withdraw within same block");

        claimReward(msg.sender);

        user.lpTokenBalance = user.lpTokenBalance - amountOutLpToken;
        user.rewardStartAt = user.lpTokenBalance * accRewardPerlpToken / 1e36;
        gauge.withdraw(amountOutLpToken);

        uint amountOutToken;
        if (token != lpToken) {
            int128 i;
            if (token == fUSDT) i = 2;
            else if (token == fUSDC) i = 1;
            else i = 0; // DAI

            uint amount = amountOutLpToken * pool.get_virtual_price() / 1e18;
            if (token != fDAI) amount /= 1e12;
            uint minAmount = amount - (amount * slippage / 10000);

            pool.remove_liquidity_one_coin(amountOutLpToken, i, minAmount, true);
            amountOutToken = token.balanceOf(address(this));
        } else {
            amountOutToken = amountOutLpToken;
        }
        token.safeTransfer(msg.sender, amountOutToken);

        emit Withdraw(address(token), amountOutToken);
    }

    function _harvest(bool isDeposit) internal override {
        // Collect CRV and WFTM from Curve
        gauge.claim_rewards();
        uint currentPool = gauge.balanceOf(address(this));

        uint WFTMAmt = WFTM.balanceOf(address(this));
        uint minSwapAmt = msg.sender == bot ? 250e17 : 125e17; // 25 : 12.5 WFTM
        if (WFTMAmt > minSwapAmt) {
            // Swap CRV to WFTM
            uint fCRVAmt = fCRV.balanceOf(address(this));
            if (fCRVAmt > 0) WFTMAmt += swap2(address(fCRV), address(WFTM), fCRVAmt);

            uint GEISTAmt = GEIST.balanceOf(address(this));
            if (GEISTAmt > 0) WFTMAmt += swap2(address(GEIST), address(WFTM), GEISTAmt);

            isDeposit; // To silence warning

            // Swap WFTM to reward token
            uint rewardTokenAmt = swap2(address(WFTM), address(rewardToken), WFTMAmt);

            // Calculate fee
            uint fee = rewardTokenAmt * yieldFeePerc / 10000;
            rewardTokenAmt -= fee;

            // Update accRewardPerlpToken
            accRewardPerlpToken += (rewardTokenAmt * 1e36 / currentPool);

            // Transfer out fee
            rewardToken.safeTransfer(treasury, fee);

            emit Harvest(WFTMAmt, rewardTokenAmt, fee);
        }
    }

    function claimReward(address account) public override virtual {
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

    function swap2(address tokenIn, address tokenOut, uint amount) internal virtual override returns (uint) {
        address[] memory path = getPath(tokenIn, tokenOut);
        return spookyRouter.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp)[1];
    }

    uint256[50] private __gap;
}
