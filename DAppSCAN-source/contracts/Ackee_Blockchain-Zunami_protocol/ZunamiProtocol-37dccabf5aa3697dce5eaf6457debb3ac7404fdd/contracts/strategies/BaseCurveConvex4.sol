//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../utils/Constants.sol";
import "../interfaces/ICurvePool4.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapRouter.sol";
import "../interfaces/IConvexBooster.sol";
import "../interfaces/IConvexMinter.sol";
import "../interfaces/IConvexRewards.sol";
import "../interfaces/IZunami.sol";

contract BaseCurveConvex4 is Context, Ownable {
    using SafeERC20 for IERC20Metadata;
    using SafeERC20 for IConvexMinter;

    uint256 private constant DENOMINATOR = 1e18;
    uint256 private constant USD_MULTIPLIER = 1e12;
    uint256 private constant DEPOSIT_DENOMINATOR = 10000; // 100%
    uint256 public minDepositAmount = 9975; // 99.75%

    address[3] public tokens;
    uint256 public usdtPoolId = 2;
    uint256 public managementFees;
    uint256 public zunamiLpInStrat = 0;

    ICurvePool4 public pool;
    IERC20Metadata public crv;
    IConvexMinter public cvx;
    IERC20Metadata public poolLP;
    IERC20Metadata public token;
    IUniswapRouter public router;
    IUniswapV2Pair public crvweth;
    IUniswapV2Pair public wethcvx;
    IUniswapV2Pair public wethusdt;
    IConvexBooster public booster;
    IConvexRewards public crvRewards;
    IERC20Metadata public extraToken;
    IUniswapV2Pair public extraPair;
    IConvexRewards public extraRewards;
    IZunami public zunami;
    uint256 public cvxPoolPID;

    event SellRewards(uint256 cvxBalance, uint256 crvBalance, uint256 extraBalance);

    constructor(
        address poolAddr,
        address poolLPAddr,
        address rewardsAddr,
        uint256 poolPID,
        address tokenAddr,
        address extraRewardsAddr,
        address extraTokenAddr,
        address extraTokenPairAddr
    ) {
        pool = ICurvePool4(poolAddr);
        poolLP = IERC20Metadata(poolLPAddr);
        crv = IERC20Metadata(Constants.CRV_ADDRESS);
        cvx = IConvexMinter(Constants.CVX_ADDRESS);
        crvweth = IUniswapV2Pair(Constants.SUSHI_CRV_WETH_ADDRESS);
        wethcvx = IUniswapV2Pair(Constants.SUSHI_WETH_CVX_ADDRESS);
        wethusdt = IUniswapV2Pair(Constants.SUSHI_WETH_USDT_ADDRESS);
        booster = IConvexBooster(Constants.CVX_BOOSTER_ADDRESS);
        crvRewards = IConvexRewards(rewardsAddr);
        router = IUniswapRouter(Constants.SUSHI_ROUTER_ADDRESS);
        cvxPoolPID = poolPID;
        token = IERC20Metadata(tokenAddr);
        extraToken = IERC20Metadata(extraTokenAddr);
        extraPair = IUniswapV2Pair(extraTokenPairAddr);
        extraRewards = IConvexRewards(extraRewardsAddr);
        tokens[0] = Constants.DAI_ADDRESS;
        tokens[1] = Constants.USDC_ADDRESS;
        tokens[2] = Constants.USDT_ADDRESS;
    }

    modifier onlyZunami() {
        require(
            _msgSender() == address(zunami),
            "CurvetokenConvex: must be called by Zunami contract"
        );
        _;
    }

    function setZunami(address zunamiAddr) external onlyOwner {
        zunami = IZunami(zunamiAddr);
    }

    function getZunamiLpInStrat() external view virtual returns (uint256){
        return zunamiLpInStrat;
    }

    function totalHoldings() public view virtual returns (uint256) {
        uint256 lpBalance = crvRewards.balanceOf(address(this));
        uint256 lpPrice = pool.get_virtual_price();
        (uint112 reserve0, uint112 reserve1,) = wethcvx.getReserves();
        uint256 cvxPrice = (reserve1 * DENOMINATOR) / reserve0;
        (reserve0, reserve1,) = crvweth.getReserves();
        uint256 crvPrice = (reserve0 * DENOMINATOR) / reserve1;
        (reserve0, reserve1,) = wethusdt.getReserves();
        uint256 ethPrice = (reserve1 * USD_MULTIPLIER * DENOMINATOR) / reserve0;
        crvPrice = (crvPrice * ethPrice) / DENOMINATOR;
        cvxPrice = (cvxPrice * ethPrice) / DENOMINATOR;
        uint256 sum = 0;
        if (address(extraPair) != address(0)) {
            uint256 extraTokenPrice = 0;
            (reserve0, reserve1,) = extraPair.getReserves();
            for (uint8 i = 0; i < 3; ++i) {
                if (extraPair.token0() == tokens[i]) {
                    if (i > 0) {
                        extraTokenPrice =
                        (reserve0 * USD_MULTIPLIER * DENOMINATOR) /
                        reserve1;
                    } else {
                        extraTokenPrice = (reserve0 * DENOMINATOR) / reserve1;
                    }
                }
                if (extraPair.token1() == tokens[i]) {
                    if (i > 0) {
                        extraTokenPrice =
                        (reserve1 * USD_MULTIPLIER * DENOMINATOR) /
                        reserve0;
                    } else {
                        extraTokenPrice = (reserve1 * DENOMINATOR) / reserve0;
                    }
                }
            }
            if (extraTokenPrice == 0) {
                if (extraPair.token0() == Constants.WETH_ADDRESS) {
                    extraTokenPrice =
                    (((reserve0 * DENOMINATOR) / reserve1) * ethPrice) /
                    DENOMINATOR;
                } else {
                    extraTokenPrice =
                    (((reserve1 * DENOMINATOR) / reserve0) * ethPrice) /
                    DENOMINATOR;
                }
            }
            sum +=
            (extraTokenPrice *
            (extraRewards.earned(address(this)) +
            extraToken.balanceOf(address(this)))) /
            DENOMINATOR;
        }
        uint256 decimalsMultiplier = 1;
        if (token.decimals() < 18) {
            decimalsMultiplier = 10 ** (18 - token.decimals());
        }
        sum += token.balanceOf(address(this)) * decimalsMultiplier;
        for (uint8 i = 0; i < 3; ++i) {
            decimalsMultiplier = 1;
            if (IERC20Metadata(tokens[i]).decimals() < 18) {
                decimalsMultiplier =
                10 ** (18 - IERC20Metadata(tokens[i]).decimals());
            }
            sum +=
            IERC20Metadata(tokens[i]).balanceOf(address(this)) *
            decimalsMultiplier;
        }
        return
        sum +
        (lpBalance *
        lpPrice +
        crvPrice *
        (crvRewards.earned(address(this)) +
        crv.balanceOf(address(this))) +
        cvxPrice *
        ((crvRewards.earned(address(this)) *
        (cvx.totalCliffs() -
        cvx.totalSupply() /
        cvx.reductionPerCliff())) /
        cvx.totalCliffs() +
        cvx.balanceOf(address(this)))) /
        DENOMINATOR;
    }

    function deposit(uint256[3] memory amounts) external virtual onlyZunami returns (uint256) {
        // check decimal amounts
        uint256 decAmounts = 0;
        for (uint8 i = 0; i < 3; ++i) {
            if (IERC20Metadata(tokens[i]).decimals() < 18) {
                decAmounts += amounts[i] * 10 ** (18 - IERC20Metadata(tokens[i]).decimals());
            } else {
                decAmounts += amounts[i];
            }
        }

        uint256[4] memory amounts4;
        for (uint8 i = 0; i < 3; ++i) {
            amounts4[i] = amounts[i];
        }

        uint256 amountsMin = decAmounts * minDepositAmount / DEPOSIT_DENOMINATOR;
        uint256 lpPrice = pool.get_virtual_price();
        uint256 depositedLp = pool.calc_token_amount(amounts4, true);

        if (depositedLp * lpPrice / 1e18 >= amountsMin) {
            for (uint8 i = 0; i < 3; ++i) {
                IERC20Metadata(tokens[i]).safeIncreaseAllowance(
                    address(pool),
                    amounts[i]
                );
            }
            uint256 depositedAmount = pool.calc_token_amount(amounts4, true);
            pool.add_liquidity(amounts4, 0);
            poolLP.safeApprove(address(booster), poolLP.balanceOf(address(this)));
            booster.depositAll(cvxPoolPID, true);
            return (depositedAmount * pool.get_virtual_price() / DENOMINATOR);
        } else {
            return (0);
        }
    }

    function withdraw(
        address depositor,
        uint256 lpShares,
        uint256[3] memory minAmounts
    ) external virtual onlyZunami returns (bool) {
        uint256[4] memory minAmounts4;
        for (uint8 i = 0; i < 3; ++i) {
            minAmounts4[i] = minAmounts[i];
        }
        uint256 crvRequiredLPs = pool.calc_token_amount(minAmounts4, false);
        uint256 depositedShare = (crvRewards.balanceOf(address(this)) *
        lpShares) / zunamiLpInStrat;

        if (depositedShare < crvRequiredLPs) {
            return false;
        }


        crvRewards.withdrawAndUnwrap(depositedShare, true);
        sellCrvCvx();

        if (address(extraToken) != address(0)) {
            sellExtraToken();
        }

        uint256[] memory userBalances = new uint256[](3);
        uint256[] memory prevBalances = new uint256[](3);
        for (uint8 i = 0; i < 3; ++i) {
            uint256 managementFee = (i == usdtPoolId) ? managementFees : 0;
            prevBalances[i] = IERC20Metadata(tokens[i]).balanceOf(
                address(this)
            );
            userBalances[i] =
            ((prevBalances[i] - managementFee) * lpShares) /
            zunamiLpInStrat;
        }

        pool.remove_liquidity(depositedShare, minAmounts4);
        sellToken();
        uint256[3] memory liqAmounts;
        for (uint256 i = 0; i < 3; ++i) {
            liqAmounts[i] =
            IERC20Metadata(tokens[i]).balanceOf(address(this)) -
            prevBalances[i];
        }

        for (uint8 i = 0; i < 3; ++i) {
            uint256 managementFee = (i == usdtPoolId) ? managementFees : 0;
            IERC20Metadata(tokens[i]).safeTransfer(
                depositor,
                liqAmounts[i] + userBalances[i] - managementFee
            );
        }
        return true;
    }

    function claimManagementFees() external virtual onlyZunami {
        uint256 stratBalance = IERC20Metadata(tokens[2]).balanceOf(address(this));
        IERC20Metadata(tokens[2]).safeTransfer(owner(), managementFees > stratBalance ? stratBalance : managementFees);
        managementFees = 0;
    }

    function sellCrvCvx() public virtual {
        uint256 cvxBalance = cvx.balanceOf(address(this));
        uint256 crvBalance = crv.balanceOf(address(this));
        if (cvxBalance == 0 || crvBalance == 0) {return;}
        cvx.safeApprove(address(router), cvxBalance);
        crv.safeApprove(address(router), crvBalance);
        uint256 usdtBalanceBefore = IERC20Metadata(tokens[2]).balanceOf(address(this));
        address[] memory path = new address[](3);
        path[0] = Constants.CVX_ADDRESS;
        path[1] = Constants.WETH_ADDRESS;
        path[2] = Constants.USDT_ADDRESS;
        router.swapExactTokensForTokens(
            cvxBalance,
            0,
            path,
            address(this),
            block.timestamp + Constants.TRADE_DEADLINE
        );

        path[0] = Constants.CRV_ADDRESS;
        path[1] = Constants.WETH_ADDRESS;
        path[2] = Constants.USDT_ADDRESS;
        router.swapExactTokensForTokens(
            crvBalance,
            0,
            path,
            address(this),
            block.timestamp + Constants.TRADE_DEADLINE
        );
        uint256 usdtBalanceAfter = IERC20Metadata(tokens[2]).balanceOf(address(this));
        managementFees = zunami.calcManagementFee(
            usdtBalanceAfter - usdtBalanceBefore
        );
        emit SellRewards(cvxBalance, crvBalance, 0);
    }

    function sellExtraToken() public virtual {
        uint256 extraBalance = extraToken.balanceOf(address(this));
        if (extraBalance == 0) {return;}
        extraToken.safeApprove(
            address(router),
            extraToken.balanceOf(address(this))
        );
        uint256 usdtBalanceBefore = IERC20Metadata(tokens[2]).balanceOf(address(this));
        uint256 usdtBalanceAfter;
        if (
            extraPair.token0() == Constants.WETH_ADDRESS ||
            extraPair.token1() == Constants.WETH_ADDRESS
        ) {
            address[] memory path = new address[](3);
            path[0] = address(extraToken);
            path[1] = Constants.WETH_ADDRESS;
            path[2] = Constants.USDT_ADDRESS;
            router.swapExactTokensForTokens(
                extraBalance,
                0,
                path,
                address(this),
                block.timestamp + Constants.TRADE_DEADLINE
            );
            usdtBalanceAfter = IERC20Metadata(tokens[2]).balanceOf(address(this));
            managementFees = zunami.calcManagementFee(
                usdtBalanceAfter - usdtBalanceBefore
            );
            return;
        }
        address[] memory path2 = new address[](2);
        path2[0] = address(extraToken);
        for (uint8 i = 0; i < 3; ++i) {
            if (
                extraPair.token0() == tokens[i] ||
                extraPair.token1() == tokens[i]
            ) {
                path2[1] = tokens[i];
            }
        }
        router.swapExactTokensForTokens(
            extraBalance,
            0,
            path2,
            address(this),
            block.timestamp + Constants.TRADE_DEADLINE
        );
        usdtBalanceAfter = IERC20Metadata(tokens[2]).balanceOf(address(this));
        managementFees = zunami.calcManagementFee(
            usdtBalanceAfter - usdtBalanceBefore
        );
    }

    function sellToken() public virtual {
        token.safeApprove(address(pool), token.balanceOf(address(this)));
        pool.exchange_underlying(3, 2, token.balanceOf(address(this)), 0);
    }

    function withdrawAll() external virtual onlyZunami {
        crvRewards.withdrawAllAndUnwrap(true);
        sellCrvCvx();
        if (address(extraToken) != address(0)) {
            sellExtraToken();
        }

        uint256 lpBalance = poolLP.balanceOf(address(this));
        uint256[4] memory minAmounts;
        pool.remove_liquidity(lpBalance, minAmounts);
        sellToken();

        for (uint8 i = 0; i < 3; ++i) {
            uint256 managementFee = (i == usdtPoolId) ? managementFees : 0;
            IERC20Metadata(tokens[i]).safeTransfer(
                _msgSender(),
                IERC20Metadata(tokens[i]).balanceOf(address(this)) -
                managementFee
            );
        }
    }

    function updateMinDepositAmount(uint256 _minDepositAmount) external onlyOwner {
        require(_minDepositAmount > 0 && _minDepositAmount <= 10000, "Wrong amount!");
        minDepositAmount = _minDepositAmount;
    }

    function updateZunamiLpInStrat(uint256 _amount, bool _isMint) external onlyZunami {
        _isMint ? (zunamiLpInStrat += _amount) :  (zunamiLpInStrat -= _amount);
    }
}
