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

contract PowerBomb is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeERC20Upgradeable for IPair;

    IERC20Upgradeable constant USDT = IERC20Upgradeable(0x3C2B8Be99c50593081EAA2A724F0B8285F5aba8f);
    IERC20Upgradeable constant USDC = IERC20Upgradeable(0x985458E523dB3d53125813eD68c274899e9DfAb4);
    IERC20Upgradeable constant SUSHI = IERC20Upgradeable(0xBEC775Cb42AbFa4288dE81F387a9b1A3c4Bc552A);
    IERC20Upgradeable constant WONE = IERC20Upgradeable(0xcF664087a5bB0237a0BAd6742852ec6c8d69A27a);
    IPair constant SLP = IPair(0x0c51171b913Db10ade3fd625548E69C9C63aFb96);
    address constant BTC = 0x3095c7557bCb296ccc6e363DE01b760bA031F2d9;
    address constant ETH = 0x6983D1E6DEf3690C4d616b13597A09e6193EA013;
    IERC20Upgradeable public rewardToken;

    IRouter constant router = IRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IMiniChef constant miniChef = IMiniChef(0x67dA5f2FfaDDfF067AB9d5F025F8810634d84287);
    IRewarder constant rewarder = IRewarder(0x25836011Bbc0d5B6db96b20361A474CbC5245b45);
    uint constant pid = 6;

    address public treasury;
    address public admin;
    uint public yieldFeePerc;
    uint public rewardWithdrawalFeePerc;
    uint public slippagePerc;

    uint public accRewardPerSLP;

    struct User {
        uint SLPBalance;
        uint rewardStartAt;
    }
    mapping(address => User) public userInfo;
    mapping(address => uint) private depositedBlock;

    // Newly add variable by upgrade contract
    uint public tvlMaxLimit;
    uint private accReward;
    mapping(address => uint) private userAccReward;
    address public helper;

    event Deposit(address tokenDeposit, uint amountToken, uint amountSLP);
    event Withdraw(address tokenWithdraw, uint amount);
    event Harvest(uint harvestedWONE, uint harvestedSUSHI, uint swappedRewardTokenAfterFee, uint fee);
    event ClaimReward(address receiver, uint claimedRewardTokenAfterFee, uint fee);

    function initialize(IERC20Upgradeable _rewardToken) external initializer {
        __Ownable_init();

        yieldFeePerc = 500;
        rewardWithdrawalFeePerc = 10;
        slippagePerc = 50;
        treasury = owner();
        admin = owner();
        rewardToken = _rewardToken;

        USDT.safeApprove(address(router), type(uint).max);
        USDC.safeApprove(address(router), type(uint).max);
        WONE.safeApprove(address(router), type(uint).max);
        SUSHI.safeApprove(address(router), type(uint).max);
        SLP.safeApprove(address(router), type(uint).max);
        SLP.safeApprove(address(miniChef), type(uint).max);
    }

    function deposit(IERC20Upgradeable token, uint amount) external {
        _deposit(token, amount, msg.sender);
    }

    function depositByHelper(IERC20Upgradeable token, uint amount, address depositor) external {
        require(msg.sender == helper, "Only helper");
        _deposit(token, amount, depositor);
    }

    function _deposit(IERC20Upgradeable token, uint amount, address depositor) private nonReentrant whenNotPaused {
        require(token == USDT || token == USDC || token == SLP, "Invalid token");
        require(getAllPoolInUSD() < tvlMaxLimit, "TVL max Limit reach");

        (uint currentPool,) = miniChef.userInfo(pid, address(this));
        if (currentPool > 0) harvest();

        token.safeTransferFrom(msg.sender, address(this), amount);
        depositedBlock[depositor] = block.number;

        if (token == USDT) {
            uint USDCAmt = swap2(address(USDT), address(USDC), amount / 2);
            router.addLiquidity(address(USDT), address(USDC), amount / 2, USDCAmt, 0, 0, address(this), block.timestamp);
        } else if (token == USDC) {
            uint USDTAmt = swap2(address(USDC), address(USDT), amount / 2);
            router.addLiquidity(address(USDC), address(USDT), amount / 2, USDTAmt, 0, 0, address(this), block.timestamp);
        }
        uint USDTBal = USDT.balanceOf(address(this));
        if(USDTBal > 0) USDT.safeTransfer(depositor, USDTBal);
        uint USDCBal = USDC.balanceOf(address(this));
        if(USDCBal > 0) USDC.safeTransfer(depositor, USDCBal);

        uint SLPAmount = SLP.balanceOf(address(this));
        miniChef.deposit(pid, SLPAmount, address(this));
        User storage user = userInfo[depositor];
        user.SLPBalance = user.SLPBalance + SLPAmount;
        user.rewardStartAt = user.rewardStartAt + (SLPAmount * accRewardPerSLP) / 1e18;

        emit Deposit(address(token), amount, SLPAmount);
    }

    function withdraw(IERC20Upgradeable token, uint amountInSLP) external nonReentrant {
        require(token == USDT || token == USDC || token == SLP, "Invalid token");
        User storage user = userInfo[msg.sender];
        require(amountInSLP > 0 || user.SLPBalance >= amountInSLP, "Invalid amountInSLP to withdraw");
        require(depositedBlock[msg.sender] != block.number, "Withdraw: within same block");

        claimReward(msg.sender);

        user.SLPBalance = user.SLPBalance - amountInSLP;
        user.rewardStartAt = user.SLPBalance * accRewardPerSLP / 1e18;
        miniChef.withdraw(pid, amountInSLP, address(this));

        uint amountInToken;
        if (token == USDT) {
            (uint USDTAmt, uint USDCAmt) = router.removeLiquidity(address(USDT), address(USDC), amountInSLP, 0, 0, address(this), block.timestamp);
            uint _USDTAmt = swap2(address(USDC), address(USDT), USDCAmt);
            amountInToken = USDTAmt + _USDTAmt;
            USDT.safeTransfer(msg.sender, amountInToken);
        } else if (token == USDC) {
            (uint USDTAmt, uint USDCAmt) = router.removeLiquidity(address(USDT), address(USDC), amountInSLP, 0, 0, address(this), block.timestamp);
            uint _USDCAmt = swap2(address(USDT), address(USDC), USDTAmt);
            amountInToken = USDCAmt + _USDCAmt;
            USDC.safeTransfer(msg.sender, amountInToken);
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
            uint rewardTokenAmt = rewardToken.balanceOf(address(this));

            address[] memory pathWONE = new address[](2);
            pathWONE[0] = address(WONE);
            pathWONE[1] = address(rewardToken);
            router.swapExactTokensForTokens(WONEAmt, 0, pathWONE, address(this), block.timestamp);

            uint SUSHIAmt = SUSHI.balanceOf(address(this));
            address[] memory pathSUSHI = new address[](3);
            pathSUSHI[0] = address(SUSHI);
            pathSUSHI[1] = address(WONE);
            pathSUSHI[2] = address(rewardToken);
            router.swapExactTokensForTokens(SUSHIAmt, 0, pathSUSHI, address(this), block.timestamp);

            rewardTokenAmt = rewardToken.balanceOf(address(this)) - rewardTokenAmt;
            accReward += rewardTokenAmt;
            uint fee = rewardTokenAmt * yieldFeePerc / 10000;
            rewardToken.safeTransfer(treasury, fee);
            rewardTokenAmt = rewardTokenAmt - fee;
            (uint currentPool,) = miniChef.userInfo(pid, address(this));
            accRewardPerSLP = accRewardPerSLP + (rewardTokenAmt * 1e18 / currentPool);

            emit Harvest(WONEAmt, SUSHIAmt, rewardTokenAmt, fee);
        }
    }

    function claimReward(address account) public {
        harvest();

        User storage user = userInfo[account];
        if (user.SLPBalance > 0) {
            uint rewardTokenAmt = (user.SLPBalance * accRewardPerSLP / 1e18) - user.rewardStartAt;
            user.rewardStartAt = user.rewardStartAt + rewardTokenAmt;
            uint fee = rewardTokenAmt * rewardWithdrawalFeePerc / 10000;
            rewardToken.safeTransfer(treasury, fee);
            rewardTokenAmt = rewardTokenAmt - fee;
            rewardToken.safeTransfer(account, rewardTokenAmt);
            userAccReward[account] += rewardTokenAmt;

            emit ClaimReward(account, rewardTokenAmt, fee);
        }
    }

    function swap2(address tokenIn, address tokenOut, uint amount) private returns (uint) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        uint amountOutMin = amount * (10000 - slippagePerc) / 10000;
        return (router.swapExactTokensForTokens(amount, amountOutMin, path, address(this), block.timestamp)[1]);
    }

    function setAdmin(address _admin) external onlyOwner {
        admin = _admin;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setHelper(address _helper) external onlyOwner {
        helper = _helper;
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

    function getAllPool() public view returns (uint amount) {
        (amount,) = miniChef.userInfo(pid, address(this));
    }

    function getPricePerFullShare() public view returns (uint) {
        (uint112 reserveUSDT, uint112 reserveUSDC,) = SLP.getReserves();
        uint totalReserve = reserveUSDT + reserveUSDC;
        return totalReserve * 1e18 / SLP.totalSupply();
    }

    /// return All pool in USD (6 decimals)
    function getAllPoolInUSD() public view returns (uint) {
        uint pool = getAllPool();
        if (pool == 0) return 0;
        return pool * getPricePerFullShare() / 1e18;
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

    function getUserBalance(address account) external view returns (uint) {
        return userInfo[account].SLPBalance;
    }

    /// return User balance in USD (6 decimals)
    function getUserBalanceInUSD(address account) external view returns (uint) {
        return userInfo[account].SLPBalance * getPricePerFullShare() / 1e18;
    }

    function getUserAccumulatedReward(address account) external view returns (uint) {
        return userAccReward[account];
    }
}
