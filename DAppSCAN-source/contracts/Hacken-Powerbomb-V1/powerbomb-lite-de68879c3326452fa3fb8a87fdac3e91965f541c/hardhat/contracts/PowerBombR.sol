// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
}

interface IPair is IERC20Upgradeable {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IMiniChef {
    struct UserInfo {
        uint amount;
        uint rewardDebt;
    }
    function userInfo(uint pid, address user) external view returns (uint, uint);
    function deposit(uint pid, uint amount, address to) external;
    function withdraw(uint pid, uint amount, address to) external;
    function harvest(uint pid, address to) external;
    function pendingSushi(uint pid, address user) external view returns (uint);
}

interface IRewarder {
    function pendingToken(uint pid, address user) external view returns (uint);
}

contract PowerBombR is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IPair;

    IERC20Upgradeable constant USDT = IERC20Upgradeable(0x3C2B8Be99c50593081EAA2A724F0B8285F5aba8f);
    IERC20Upgradeable constant USDC = IERC20Upgradeable(0x985458E523dB3d53125813eD68c274899e9DfAb4);
    IERC20Upgradeable constant SUSHI = IERC20Upgradeable(0xBEC775Cb42AbFa4288dE81F387a9b1A3c4Bc552A);
    IERC20Upgradeable constant WONE = IERC20Upgradeable(0xcF664087a5bB0237a0BAd6742852ec6c8d69A27a);
    IERC20Upgradeable constant WBTC = IERC20Upgradeable(0x3095c7557bCb296ccc6e363DE01b760bA031F2d9);
    IERC20Upgradeable constant WETH = IERC20Upgradeable(0x6983D1E6DEf3690C4d616b13597A09e6193EA013);
    IPair constant SLP = IPair(0x39bE7c95276954a6f7070F9BAa38db2123691Ed0);

    IRouter constant router = IRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IMiniChef constant miniChef = IMiniChef(0x67dA5f2FfaDDfF067AB9d5F025F8810634d84287);
    IRewarder constant rewarder = IRewarder(0x25836011Bbc0d5B6db96b20361A474CbC5245b45);
    uint constant pid = 10;

    address public treasury;
    address public admin;
    address public proxy;
    uint public yieldFeePerc;
    uint public rewardWithdrawalFeePerc;
    uint public slippagePerc;

    uint private accReward;
    uint public accRewardPerSLP;
    mapping(address => uint) private userAccReward;
    uint public tvlMaxLimit;

    struct User {
        uint SLPBalance;
        uint rewardStartAt;
    }
    mapping(address => User) public userInfo;
    mapping(address => uint) private depositedBlock;

    event Deposit(address tokenDeposit, uint amountToken, uint amountSLP);
    event Withdraw(address tokenWithdraw, uint amount);
    event Harvest(uint harvestedWONE, uint harvestedSUSHI, uint swappedUSDTAfterFee, uint fee);
    event ClaimReward(address receiver, uint claimedUSSCAfterFee, uint fee);

    function initialize() external initializer {
        __Ownable_init();

        yieldFeePerc = 500;
        rewardWithdrawalFeePerc = 10;
        slippagePerc = 50;
        treasury = owner();
        admin = owner();
        tvlMaxLimit = 1e12; // 1M in 6 decimals

        WBTC.safeApprove(address(router), type(uint).max);
        WETH.safeApprove(address(router), type(uint).max);
        USDT.safeApprove(address(router), type(uint).max);
        WONE.safeApprove(address(router), type(uint).max);
        SUSHI.safeApprove(address(router), type(uint).max);
        SLP.safeApprove(address(router), type(uint).max);
        SLP.safeApprove(address(miniChef), type(uint).max);
    }

    function deposit(IERC20Upgradeable token, uint amount, uint[] calldata tokenPrice) external {
        _deposit(token, amount, msg.sender, tokenPrice);
    }

    function depositByProxy(IERC20Upgradeable token, uint amount, address depositor, uint[] calldata tokenPrice) external {
        require(msg.sender == proxy, "Only proxy");
        _deposit(token, amount, depositor, tokenPrice);
    }

    function _deposit(
        IERC20Upgradeable token, uint amount, address depositor, uint[] calldata tokenPrice
    ) private nonReentrant whenNotPaused {
        require(token == WBTC || token == WETH || token == USDT || token == SLP, "Invalid token");
        require(getAllPoolInUSD(tokenPrice[0]) < tvlMaxLimit, "TVL max Limit reach");

        (uint currentPool,) = miniChef.userInfo(pid, address(this));
        if (currentPool > 0) harvest();

        token.safeTransferFrom(msg.sender, address(this), amount);
        depositedBlock[depositor] = block.number;

        if (token == WBTC) {
            uint amountOutMin = amount * tokenPrice[1] / 1e8;
            uint WETHAmt = swap(address(WBTC), address(WETH), amount / 2, amountOutMin);
            router.addLiquidity(address(WBTC), address(WETH), amount / 2, WETHAmt, 0, 0, address(this), block.timestamp);
        } else if (token == WETH) {
            uint amountOutMin = amount * tokenPrice[1] / 1e18;
            uint WBTCAmt = swap(address(WETH), address(WBTC), amount / 2, amountOutMin);
            router.addLiquidity(address(WETH), address(WBTC), amount / 2, WBTCAmt, 0, 0, address(this), block.timestamp);
        } else if (token == USDT) {
            uint amountOutMinWONE = amount * tokenPrice[1] / 1e6;
            uint WONEAmt = swap(address(USDT), address(WONE), amount, amountOutMinWONE);
            uint amountOutMinWETH = WONEAmt * tokenPrice[2] / 1e18;
            uint WETHAmt = swap(address(WONE), address(WETH), WONEAmt, amountOutMinWETH);
            uint halfWETH = WETHAmt / 2;
            uint amountOutMinWBTC = halfWETH * tokenPrice[3] / 1e18;
            uint WBTCAmt = swap(address(WETH), address(WBTC), halfWETH, amountOutMinWBTC);
            router.addLiquidity(address(WBTC), address(WETH), WBTCAmt, halfWETH, 0, 0, address(this), block.timestamp);
        }
        uint WBTCBal = WBTC.balanceOf(address(this));
        if(WBTCBal > 0) WBTC.safeTransfer(depositor, WBTCBal);
        uint WETHBal = WETH.balanceOf(address(this));
        if(WETHBal > 0) WETH.safeTransfer(depositor, WETHBal);
        uint USDTBal = USDT.balanceOf(address(this));
        if(USDTBal > 0) USDT.safeTransfer(depositor, USDTBal);

        uint SLPAmount = SLP.balanceOf(address(this));
        miniChef.deposit(pid, SLPAmount, address(this));
        User storage user = userInfo[depositor];
        user.SLPBalance = user.SLPBalance + SLPAmount;
        user.rewardStartAt = user.rewardStartAt + (SLPAmount * accRewardPerSLP) / 1e18;

        emit Deposit(address(token), amount, SLPAmount);
    }

    function withdraw(IERC20Upgradeable token, uint amountInSLP, uint[] calldata tokenPriceMin) external nonReentrant {
        require(token == WBTC || token == WETH || token == USDT || token == SLP, "Invalid token");
        require(amountInSLP > 0, "Withdraw: invalid amountInSLP");
        User storage user = userInfo[msg.sender];
        require(user.SLPBalance > 0, "Withdraw: nothing to withdraw");
        require(depositedBlock[msg.sender] != block.number, "Withdraw: within same block");

        claimReward(msg.sender);

        user.SLPBalance = user.SLPBalance - amountInSLP;
        user.rewardStartAt = user.SLPBalance * accRewardPerSLP / 1e18;
        miniChef.withdraw(pid, amountInSLP, address(this));
        (uint WBTCAmt, uint WETHAmt) = router.removeLiquidity(address(WBTC), address(WETH), amountInSLP, 0, 0, address(this), block.timestamp);

        uint amountInToken;
        if (token == WBTC) {
            uint amountOutMin = WETHAmt * tokenPriceMin[0] / 1e18;
            uint _WBTCAmt = swap(address(WETH), address(WBTC), WETHAmt, amountOutMin);
            amountInToken = WBTCAmt + _WBTCAmt;
            WBTC.safeTransfer(msg.sender, amountInToken);
        } else if (token == WETH) {
            uint amountOutMin = WBTCAmt * tokenPriceMin[0] / 1e8;
            uint _WETHAmt = swap(address(WBTC), address(WETH), WBTCAmt, amountOutMin);
            amountInToken = WBTCAmt + _WETHAmt;
            USDT.safeTransfer(msg.sender, amountInToken);
        } else if (token == USDT) {
            uint amountOutMinWETH = WBTCAmt * tokenPriceMin[0] / 1e8;
            uint _WETHAmt = swap(address(WBTC), address(WETH), WBTCAmt, amountOutMinWETH);
            uint totalWETH = WETHAmt + _WETHAmt;
            uint amountOutMinWONE = totalWETH * tokenPriceMin[1] / 1e18;
            uint WONEAmt = swap(address(WETH), address(WONE), totalWETH, amountOutMinWONE);
            uint amountOutMinUSDT = WONEAmt * tokenPriceMin[2] / 1e18;
            amountInToken = swap(address(WONE), address(USDT), WONEAmt, amountOutMinUSDT);
            USDT.safeTransfer(msg.sender, amountInToken);
        } else {
            amountInToken = amountInSLP;
            SLP.safeTransfer(msg.sender, amountInToken);
        }

        emit Withdraw(address(token), amountInToken);
    }

    function harvest() public {
        miniChef.harvest(pid, address(this));

        uint WONEAmt = WONE.balanceOf(address(this));
        if (WONEAmt > 1e18) {
            uint USDTAmt = USDT.balanceOf(address(this));

            address[] memory pathWONE = new address[](2);
            pathWONE[0] = address(WONE);
            pathWONE[1] = address(USDT);
            router.swapExactTokensForTokens(WONEAmt, 0, pathWONE, address(this), block.timestamp);

            uint SUSHIAmt = SUSHI.balanceOf(address(this));
            address[] memory pathSUSHI = new address[](3);
            pathSUSHI[0] = address(SUSHI);
            pathSUSHI[1] = address(WONE);
            pathSUSHI[2] = address(USDT);
            router.swapExactTokensForTokens(SUSHIAmt, 0, pathSUSHI, address(this), block.timestamp);

            USDTAmt = USDT.balanceOf(address(this)) - USDTAmt;
            accReward += USDTAmt;
            uint fee = USDTAmt * yieldFeePerc / 10000;
            USDT.safeTransfer(treasury, fee);
            USDTAmt = USDTAmt - fee;
            (uint currentPool,) = miniChef.userInfo(pid, address(this));
            accRewardPerSLP = accRewardPerSLP + (USDTAmt * 1e18 / currentPool);

            emit Harvest(WONEAmt, SUSHIAmt, USDTAmt, fee);
        }
    }

    function claimReward(address account) public {
        harvest();

        User storage user = userInfo[account];
        if (user.SLPBalance > 0) {
            uint USDTAmt = (user.SLPBalance * accRewardPerSLP / 1e18) - user.rewardStartAt;
            user.rewardStartAt = user.rewardStartAt + USDTAmt;
            uint fee = USDTAmt * rewardWithdrawalFeePerc / 10000;
            USDT.safeTransfer(treasury, fee);
            USDTAmt = USDTAmt - fee;
            USDT.safeTransfer(account, USDTAmt);
            userAccReward[account] += USDTAmt;

            emit ClaimReward(account, USDTAmt, fee);
        }
    }

    function swap(address tokenIn, address tokenOut, uint amount, uint amountOutMin) private returns (uint) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        return (router.swapExactTokensForTokens(amount, amountOutMin, path, address(this), block.timestamp)[1]);
    }

    function setAdmin(address _admin) external onlyOwner {
        admin = _admin;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setProxy(address _proxy) external onlyOwner {
        proxy = _proxy;
    }

    function setYieldFeePerc(uint _yieldFeePerc) external onlyOwner {
        yieldFeePerc = _yieldFeePerc;
    }

    function setRewardWithdrawalFeePerc(uint _rewardWithdrawalFeePerc) external onlyOwner {
        rewardWithdrawalFeePerc = _rewardWithdrawalFeePerc;
    }

    function setSlippagePerc(uint _slippagePerc) external onlyOwner {
        slippagePerc = _slippagePerc;
    }

    /// @param _tvlMaxLimit Max limit for TVL in this contract (6 decimals) 
    function setTVLMaxLimit(uint _tvlMaxLimit) external onlyOwner {
        tvlMaxLimit = _tvlMaxLimit;
    }

    function getPath(address from, address to) private pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = from;
        path[1] = to;
    }

    function getAllPool() public view returns (uint amount) {
        (amount,) = miniChef.userInfo(pid, address(this));
    }

    /// return All pool in USD (6 decimals, not including rewards)
    function getAllPoolInUSD(uint WONEPriceInUSD) public view returns (uint) {
        if (getAllPool() == 0) return 0;
        (uint112 reserveWBTC, uint112 reserveWETH,) = SLP.getReserves();
        uint WETHPerWBTC = router.getAmountsOut(1e8, getPath(address(WBTC), address(WETH)))[1];
        uint WETHAmt = reserveWBTC * WETHPerWBTC / 1e8;
        uint WONEPerWETH = router.getAmountsOut(1e18, getPath(address(WETH), address(WONE)))[1];
        uint WONEAmt = (WETHAmt + reserveWETH) * WONEPerWETH / 1e18;
        uint share = WONEAmt * getAllPool() / SLP.totalSupply();
        return share * WONEPriceInUSD / 1e18;
    }

    function getPricePerFullShare(uint WONEPriceInUSD) public view returns (uint) {
        if (getAllPool() == 0) return 0;
        return getAllPoolInUSD(WONEPriceInUSD) * 1e18 / getAllPool();
    }

    function getPoolPendingReward() external view returns (uint pendingWONE, uint pendingSUSHI) {
        pendingWONE = rewarder.pendingToken(pid, address(this));
        pendingWONE += WONE.balanceOf(address(this));

        pendingSUSHI = miniChef.pendingSushi(pid, address(this));
        pendingSUSHI += SUSHI.balanceOf(address(this));
    }

    function getPoolAccumulatedReward() external view returns (uint) {
        return accReward;
    }

    function getUserPendingReward(address account) external view returns (uint) {
        User storage user = userInfo[account];
        return (user.SLPBalance * accRewardPerSLP / 1e18) - user.rewardStartAt;
    }

    function getUserBalanceInSLP(address account) external view returns (uint) {
        return userInfo[account].SLPBalance;
    }

    function getUserBalanceInUSD(address account, uint WONEPriceInUSD) external view returns (uint) {
        return userInfo[account].SLPBalance * getPricePerFullShare(WONEPriceInUSD) / 1e18; // (6 decimals)
    }

    function getUserAccumulatedReward(address account) external view returns (uint) {
        return userAccReward[account];
    }
}
