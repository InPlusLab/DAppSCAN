// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
}

interface IPool {
    function add_liquidity(uint[3] memory amounts, uint _min_mint_amount) external returns (uint);
    function remove_liquidity_one_coin(uint _token_amount, int128 i, uint _min_amount) external returns (uint);
    function get_virtual_price() external view returns (uint);
}

interface IGauge {
    function deposit(uint amount) external;
    function withdraw(uint amount) external;
    function claim_rewards() external;
    function claimable_reward_write(address _addr, address _token) external returns (uint);
    function balanceOf(address account) external view returns (uint);
}

interface ILendingPool {
    function deposit(address asset, uint amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint amount, address to) external;
    function getReserveData(address asset) external view returns (
        uint, uint128, uint128, uint128, uint128, uint128, uint40, address
    );
}

interface IIncentivesController {
    function getRewardsBalance(address[] calldata assets, address user) external view returns (uint);
    function claimRewards(address[] calldata assets, uint amount, address to) external returns (uint);
}

contract PowerBombOneCurve is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable constant USDT = IERC20Upgradeable(0x3C2B8Be99c50593081EAA2A724F0B8285F5aba8f);
    IERC20Upgradeable constant USDC = IERC20Upgradeable(0x985458E523dB3d53125813eD68c274899e9DfAb4);
    IERC20Upgradeable constant DAI = IERC20Upgradeable(0xEf977d2f931C1978Db5F6747666fa1eACB0d0339);
    IERC20Upgradeable constant WONE = IERC20Upgradeable(0xcF664087a5bB0237a0BAd6742852ec6c8d69A27a);
    IERC20Upgradeable constant CRV = IERC20Upgradeable(0x352cd428EFd6F31B5cae636928b7B84149cF369F);
    IERC20Upgradeable public lpToken;
    IERC20Upgradeable public rewardToken;

    IRouter constant router = IRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IPool public pool;
    IGauge public gauge;

    address public treasury;
    address public proxy;
    
    uint public yieldFeePerc;
    uint public rewardWithdrawalFeePerc; // Depreciated
    uint public slippagePerc;
    uint public tvlMaxLimit;

    uint public accRewardPerlpToken;
    mapping(address => uint) private userAccReward;
    ILendingPool public lendingPool; // Aave Lending Pool
    IERC20Upgradeable public ibRewardToken; // aToken
    IIncentivesController public incentivesController; // To claim rewards

    struct User {
        uint lpTokenBalance;
        uint rewardStartAt;
    }
    mapping(address => User) public userInfo;
    mapping(address => uint) private depositedBlock;

    event Deposit(address tokenDeposit, uint amountToken, uint amountlpToken);
    event Withdraw(address tokenWithdraw, uint amountToken);
    event Harvest(uint harvestedfarmToken, uint swappedRewardTokenAfterFee, uint fee);
    event ClaimReward(address receiver, uint claimedIbRewardTokenAfterFee, uint rewardToken);
    event SetTreasury(address oldTreasury, address newTreasury);
    event SetProxy(address oldProxy, address newProxy);
    event SetYieldFeePerc(uint oldYieldFeePerc, uint newYieldFeePerc);
    event SetSlippagePerc(uint oldSlippagePerc, uint newSlippagePerc);
    event SetTVLMaxLimit(uint oldTVLMaxLimit, uint newTVLMaxLimit);

    function initialize(
        address _pool, IGauge _gauge,
        IERC20Upgradeable _rewardToken
    ) external initializer {
        __Ownable_init();

        pool = IPool(_pool);
        gauge = _gauge;
        lpToken = IERC20Upgradeable(_pool);

        yieldFeePerc = 500;
        rewardWithdrawalFeePerc = 10;
        slippagePerc = 50;
        treasury = owner();
        rewardToken = _rewardToken;
        // (,,,,,,,address ibRewardTokenAddr) = lendingPool.getReserveData(address(_rewardToken));
        // ibRewardToken = IERC20Upgradeable(ibRewardTokenAddr);
        tvlMaxLimit = 5000000e6;

        USDT.safeApprove(address(pool), type(uint).max);
        USDC.safeApprove(address(pool), type(uint).max);
        DAI.safeApprove(address(pool), type(uint).max);
        lpToken.safeApprove(address(pool), type(uint).max);
        lpToken.safeApprove(address(gauge), type(uint).max);
        WONE.safeApprove(address(router), type(uint).max);
        // rewardToken.safeApprove(address(lendingPool), type(uint).max);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function deposit(IERC20Upgradeable token, uint amount, uint slippage) external {
        _deposit(token, amount, msg.sender, slippage);
    }

    function depositByProxy(IERC20Upgradeable token, uint amount, address depositor, uint slippage) external {
        require(msg.sender == proxy, "Only proxy");
        _deposit(token, amount, depositor, slippage);
    }

    function _deposit(IERC20Upgradeable token, uint amount, address depositor, uint slippage) private nonReentrant whenNotPaused {
        require(token == USDT || token == USDC || token == DAI || token == lpToken, "Invalid token");
        require(amount > 0, "Invalid amount");
        require(getAllPoolInUSD() < tvlMaxLimit, "TVL max Limit reach");

        uint currentPool = gauge.balanceOf(address(this));
        if (currentPool > 0) harvest();

        token.safeTransferFrom(msg.sender, address(this), amount);
        depositedBlock[depositor] = block.number;

        uint lpTokenAmt;
        if (token != lpToken) {
            uint[3] memory amounts;
            if (token == USDT) amounts[2] = amount;
            else if (token == USDC) amounts[1] = amount;
            else if (token == DAI) amounts[0] = amount;

            if (token != DAI) amount *= 1e12;
            uint estimatedMintAmt = amount * 1e18 / pool.get_virtual_price();
            uint minMintAmt = estimatedMintAmt - (estimatedMintAmt * slippage / 10000);
            
            lpTokenAmt = pool.add_liquidity(amounts, minMintAmt);
        } else {
            lpTokenAmt = amount;
        }

        gauge.deposit(lpTokenAmt);
        User storage user = userInfo[depositor];
        user.lpTokenBalance += lpTokenAmt;
        user.rewardStartAt += (lpTokenAmt * accRewardPerlpToken / 1e36);

        emit Deposit(address(token), amount, lpTokenAmt);
    }

    function withdraw(IERC20Upgradeable token, uint amountOutLpToken, uint slippage) external nonReentrant {
        require(token == USDT || token == USDC || token == DAI || token == lpToken, "Invalid token");
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
            if (token == USDT) i = 2;
            else if (token == USDC) i = 1;
            else i = 0; // DAI

            uint amount = amountOutLpToken * pool.get_virtual_price() / 1e18;
            if (token != DAI) amount /= 1e12;
            uint minAmount = amount - (amount * slippage / 10000);

            pool.remove_liquidity_one_coin(amountOutLpToken, i, minAmount);
            amountOutToken = token.balanceOf(address(this));
        } else {
            amountOutToken = amountOutLpToken;
        }
        token.safeTransfer(msg.sender, amountOutToken);

        emit Withdraw(address(token), amountOutToken);
    }

    function harvest() public {
        // Collect CRV & WONE token from Curve
        gauge.claim_rewards();

        // Only CRV-ETH pool in Sushi at the moment, waiting for more liquidity first
        // uint CRVAmt = CRV.balanceOf(address(this));
        // if (CRVAmt > 1e18) {
        //     address[] memory path = new address[](3);
        //     path[0] = address(CRV);
        //     path[1] = 0x6983D1E6DEf3690C4d616b13597A09e6193EA013; // 1ETH
        //     path[2] = address(WONE);
        //     router.swapExactTokensForTokens(CRVAmt, 0, path, address(this), block.timestamp);
        // }

        uint WONEAmt = WONE.balanceOf(address(this));
        if (WONEAmt > 10e18) {
            // Swap WONE to reward token
            uint rewardTokenAmt = swap2(address(WONE), address(rewardToken), WONEAmt);

            // Calculate fee
            uint fee = rewardTokenAmt * yieldFeePerc / 10000;
            rewardTokenAmt -= fee;
            // ibRewardTokenBaseAmt += rewardTokenAmt; // Since 1:1 token:aToken

            // Update accRewardPerlpToken
            uint currentPool = gauge.balanceOf(address(this));
            accRewardPerlpToken += (rewardTokenAmt * 1e36 / currentPool);

            // Collect WONE reward from Aave
            // address[] memory assets = new address[](1);
            // assets[0] = address(ibRewardToken);
            // uint unclaimedRewardsAmt = incentivesController.getRewardsBalance(assets, address(this)); // in WONE
            // if (unclaimedRewardsAmt > 10e18) {
            //     uint _WONEAmt = incentivesController.claimRewards(assets, unclaimedRewardsAmt, address(this));

            //     // Swap WONE to rewardToken
            //     uint _rewardTokenAmt = swap2(address(WONE), address(rewardToken), _WONEAmt);

            //     // Calculate fee
            //     uint _fee = _rewardTokenAmt * yieldFeePerc / 10000;
            //     rewardTokenAmt += (_rewardTokenAmt - _fee);
            //     fee += _fee;
            // }

            // Transfer out fee
            rewardToken.safeTransfer(treasury, fee);

            // Deposit reward token into Aave to get interest bearing aToken
            // lendingPool.deposit(address(rewardToken), rewardTokenAmt, address(this), 0);

            emit Harvest(WONEAmt, rewardTokenAmt, fee);
        }
    }

    function claimReward(address account) public {
        harvest();

        User storage user = userInfo[account];
        if (user.lpTokenBalance > 0) {
            // Calculate user reward
            uint ibRewardTokenAmt = (user.lpTokenBalance * accRewardPerlpToken / 1e36) - user.rewardStartAt;
            if (ibRewardTokenAmt > 0) {

                // Calculate extra reward
                // uint rewardPerc = ibRewardTokenAmt * 1e18 / ibRewardTokenBaseAmt;

                // uint ibRewardTokenBal = ibRewardToken.balanceOf(address(this));
                // uint extraIbRewardTokenAmt;
                // if (ibRewardTokenBal > ibRewardTokenBaseAmt) {
                //     extraIbRewardTokenAmt = ibRewardTokenBal - ibRewardTokenBaseAmt;
                // }

                user.rewardStartAt += ibRewardTokenAmt;
                // ibRewardTokenBaseAmt -= ibRewardTokenAmt;
                // ibRewardTokenAmt += (extraIbRewardTokenAmt * rewardPerc / 1e18);

                // Withdraw ibRewardToken to rewardToken
                // lendingPool.withdraw(address(rewardToken), ibRewardTokenAmt, address(this));

                // Transfer rewardToken to user
                // uint rewardTokenAmt = rewardToken.balanceOf(address(this));
                uint rewardTokenAmt = ibRewardTokenAmt; // Temporary use for replacing above line code
                rewardToken.safeTransfer(account, rewardTokenAmt);
                userAccReward[account] += rewardTokenAmt;

                emit ClaimReward(account, ibRewardTokenAmt, rewardTokenAmt);
            }
        }
    }

    function swap2(address tokenIn, address tokenOut, uint amount) private returns (uint) {
        address[] memory path = getPath(tokenIn, tokenOut);
        return router.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp)[1];
    }
    
    function setTreasury(address _treasury) external onlyOwner {
        address oldTreasury = treasury;
        treasury = _treasury;

        emit SetTreasury(oldTreasury, _treasury);
    }

    function setProxy(address _proxy) external onlyOwner {
        address oldProxy = proxy;
        proxy = _proxy;

        emit SetProxy(oldProxy, _proxy);
    }

    function setYieldFeePerc(uint _yieldFeePerc) external onlyOwner {
        require(_yieldFeePerc <= 2000, "Invalid yield fee percentage");
        uint oldYieldFeePerc = yieldFeePerc;
        yieldFeePerc = _yieldFeePerc;

        emit SetYieldFeePerc(oldYieldFeePerc, _yieldFeePerc);
    }

    function setSlippagePerc(uint _slippagePerc) external onlyOwner {
        uint oldSlippagePerc = slippagePerc;
        slippagePerc = _slippagePerc;

        emit SetSlippagePerc(oldSlippagePerc, _slippagePerc);
    }

    /// @param _tvlMaxLimit Max limit for TVL in this contract (6 decimals) 
    function setTVLMaxLimit(uint _tvlMaxLimit) external onlyOwner {
        uint oldTVLMaxLimit = tvlMaxLimit;
        tvlMaxLimit = _tvlMaxLimit;

        emit SetTVLMaxLimit(oldTVLMaxLimit, _tvlMaxLimit);
    }

    function pauseContract() external onlyOwner {
        _pause();
    }

    function unpauseContract() external onlyOwner {
        _unpause();
    }

    function getPath(address tokenIn, address tokenOut) private pure returns (address[] memory path) {
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    function getAllPool() public view returns (uint) {
        return gauge.balanceOf(address(this));
    }

    /// @return Price per full share in USD (6 decimals)
    function getPricePerFullShareInUSD() public view returns (uint) {
        return pool.get_virtual_price() / 1e12;
    }

    /// @return All pool in USD (6 decimals)
    function getAllPoolInUSD() public view returns (uint) {
        uint allPool = getAllPool();
        if (allPool == 0) return 0;
        return allPool * getPricePerFullShareInUSD() / 1e18;
    }

    function getPoolPendingReward(IERC20Upgradeable pendingRewardToken) external returns (uint) {
        uint pendingRewardFromCurve = gauge.claimable_reward_write(address(this), address(pendingRewardToken));
        return pendingRewardFromCurve + pendingRewardToken.balanceOf(address(this));
    }

    /// @return ibRewardTokenAmt User pending reward (decimal follow reward token)
    function getUserPendingReward(address account) external view returns (uint ibRewardTokenAmt) {
        User storage user = userInfo[account];
        ibRewardTokenAmt = (user.lpTokenBalance * accRewardPerlpToken / 1e36) - user.rewardStartAt;
        // if (ibRewardTokenAmt != 0) {
        //     uint rewardPerc = ibRewardTokenAmt * 1e18 / ibRewardTokenBaseAmt;
        //     uint ibRewardTokenBal = ibRewardToken.balanceOf(address(this));
        //     if (ibRewardTokenBal > ibRewardTokenBaseAmt) {
        //         uint extraIbRewardTokenAmt = ibRewardTokenBal - ibRewardTokenBaseAmt;
        //         ibRewardTokenAmt += (extraIbRewardTokenAmt * rewardPerc / 1e18);
        //     }
        // }
    }

    function getUserBalance(address account) external view returns (uint) {
        return userInfo[account].lpTokenBalance;
    }

    /// @return User balance in USD (6 decimals)
    function getUserBalanceInUSD(address account) external view returns (uint) {
        return userInfo[account].lpTokenBalance * getPricePerFullShareInUSD() / 1e18;
    }

    /// @return User accumulated reward (decimal follow reward token)
    function getUserAccumulatedReward(address account) external view returns (uint) {
        return userAccReward[account];
    }
}
