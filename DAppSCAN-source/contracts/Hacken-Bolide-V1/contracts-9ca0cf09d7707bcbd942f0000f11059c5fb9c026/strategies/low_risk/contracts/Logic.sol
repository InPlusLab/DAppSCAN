// SPDX-License-Identifier: MIT

pragma solidity "0.8.13";
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IStorage {
    function takeToken(uint256 amount, address token) external;

    function returnToken(uint256 amount, address token) external;

    function addEarn(uint256 amount) external;
}

interface IDistribution {
    function enterMarkets(address[] calldata vTokens) external returns (uint256[] memory);

    function markets(address vTokenAddress)
        external
        view
        returns (
            bool,
            uint256,
            bool
        );

    function claimVenus(address holder) external;

    function claimVenus(address holder, address[] memory vTokens) external;
}

interface IMasterChef {
    function poolInfo(uint256 _pid)
        external
        view
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accCakePerShare
        );

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function enterStaking(uint256 _amount) external;

    function leaveStaking(uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function userInfo(uint256 _pid, address account) external view returns (uint256, uint256);
}

interface IVToken {
    function mint(uint256 mintAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function mint() external payable;

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external returns (uint256);

    function borrowBalanceCurrent(address account) external returns (uint256);

    function repayBorrow() external payable;
}

interface IPancakePair {
    function token0() external view returns (address);

    function token1() external view returns (address);
}

interface IPancakeRouter01 {
    function WETH() external pure returns (address);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

contract Logic is Ownable {
    using SafeERC20 for IERC20;

    struct ReserveLiquidity {
        address tokenA;
        address tokenB;
        address vTokenA;
        address vTokenB;
        address swap;
        address swapMaster;
        address lpToken;
        uint256 poolID;
        address[][] path;
    }

    address private _storage;
    address private blid;
    address private admin;
    address private venusController;
    address private pancake;
    address private apeswap;
    address private pancakeMaster;
    address private apeswapMaster;
    address private expenseAddress;
    address private vBNB;
    mapping(address => bool) private usedVTokens;
    mapping(address => address) private VTokens;

    ReserveLiquidity[] reserves;

    event SetAdmin(address admin);
    event SetBLID(address _blid);
    event SetStorage(address _storage);

    constructor(
        address _expenseAddress,
        address _venusController,
        address pancakeRouter,
        address apeswapRouter,
        address pancakeMaster_,
        address apeswapMaster_
    ) {
        expenseAddress = _expenseAddress;
        venusController = _venusController;

        apeswap = apeswapRouter;
        pancake = pancakeRouter;
        pancakeMaster = pancakeMaster_;
        apeswapMaster = apeswapMaster_;
    }

    fallback() external payable {}

    receive() external payable {}

    modifier onlyOwnerAndAdmin() {
        require(msg.sender == owner() || msg.sender == admin, "E1");
        _;
    }

    modifier onlyStorage() {
        require(msg.sender == _storage, "E1");
        _;
    }

    modifier isUsedVToken(address vToken) {
        require(usedVTokens[vToken], "E2");
        _;
    }

    modifier isUsedSwap(address swap) {
        require(swap == apeswap || swap == pancake, "E3");
        _;
    }

    modifier isUsedMaster(address swap) {
        require(swap == pancakeMaster || apeswapMaster == swap, "E4");
        _;
    }

    /**
     * @notice Add VToken in Contract and approve token  for storage, venus,
     * pancakeswap/apeswap router, and pancakeswap/apeswap master(Main Staking contract)
     * @param token Address of Token for deposited
     * @param vToken Address of VToken
     */
    function addVTokens(address token, address vToken) external onlyOwner {
        bool _isUsedVToken;
        (_isUsedVToken, , ) = IDistribution(venusController).markets(vToken);
        require(_isUsedVToken, "E5");
        if ((token) != address(0)) {
            IERC20(token).approve(vToken, type(uint256).max);
            IERC20(token).approve(apeswap, type(uint256).max);
            IERC20(token).approve(pancake, type(uint256).max);
            IERC20(token).approve(_storage, type(uint256).max);
            IERC20(token).approve(pancakeMaster, type(uint256).max);
            IERC20(token).approve(apeswapMaster, type(uint256).max);
            VTokens[token] = vToken;
        } else {
            vBNB = vToken;
        }
        usedVTokens[vToken] = true;
    }

    /**
     * @notice Set blid in contract and approve blid for storage, venus, pancakeswap/apeswap
     * router, and pancakeswap/apeswap master(Main Staking contract), you can call the
     * function once
     * @param blid_ Adrees of BLID
     */
    function setBLID(address blid_) external onlyOwner {
        require(blid == address(0), "E6");
        blid = blid_;
        IERC20(blid).safeApprove(apeswap, type(uint256).max);
        IERC20(blid).safeApprove(pancake, type(uint256).max);
        IERC20(blid).safeApprove(pancakeMaster, type(uint256).max);
        IERC20(blid).safeApprove(apeswapMaster, type(uint256).max);
        IERC20(blid).safeApprove(_storage, type(uint256).max);
        emit SetBLID(blid_);
    }

    /**
     * @notice Set storage, you can call the function once
     * @param storage_ Addres of Storage Contract
     */
    function setStorage(address storage_) external onlyOwner {
        require(_storage == address(0), "E7");
        _storage = storage_;
        emit SetStorage(storage_);
    }

    /**
     * @notice Approve token for storage, venus, pancakeswap/apeswap router,
     * and pancakeswap/apeswap master(Main Staking contract)
     * @param token  Address of Token that is approved
     */
    function approveTokenForSwap(address token) external onlyOwner {
        (IERC20(token).approve(apeswap, type(uint256).max));
        (IERC20(token).approve(pancake, type(uint256).max));
        (IERC20(token).approve(pancakeMaster, type(uint256).max));
        (IERC20(token).approve(apeswapMaster, type(uint256).max));
    }

    /**
     * @notice Frees up tokens for the user, but Storage doesn't transfer token for the user,
     * only Storage can this function, after calling this function Storage transfer
     * from Logic to user token.
     * @param amount Amount of token
     * @param token Address of token
     */
    function returnToken(uint256 amount, address token) external payable onlyStorage {
        uint256 takeFromVenus = 0;
        uint256 length = reserves.length;
        //check logic balance
        if (IERC20(token).balanceOf(address(this)) >= amount) {
            return;
        }
        //loop by reserves lp token
        for (uint256 i = 0; i < length; i++) {
            address[] memory path = findPath(i, token); // get path for router
            ReserveLiquidity memory reserve = reserves[i];
            uint256 lpAmount = getPriceFromTokenToLp(
                reserve.lpToken,
                amount - takeFromVenus,
                token,
                reserve.swap,
                path
            ); //get amount of lp token that need for reedem liqudity

            //get how many deposited to farming
            (uint256 depositedLp, ) = IMasterChef(reserve.swapMaster).userInfo(reserve.poolID, address(this));
            if (depositedLp == 0) continue;
            // if deposited LP tokens don't enough  for repay borrow and for reedem token then only repay
            // borow and continue loop, else repay borow, reedem token and break loop
            if (lpAmount >= depositedLp) {
                takeFromVenus += getPriceFromLpToToken(
                    reserve.lpToken,
                    depositedLp,
                    token,
                    reserve.swap,
                    path
                );
                withdrawAndRepay(reserve, depositedLp);
            } else {
                withdrawAndRepay(reserve, lpAmount);

                // get supplied token and break loop
                IVToken(VTokens[token]).redeemUnderlying(amount);
                return;
            }
        }
        //try get supplied token
        IVToken(VTokens[token]).redeemUnderlying(amount);
        //if get money
        if (IERC20(token).balanceOf(address(this)) >= amount) {
            return;
        }
        revert("no money");
    }

    /**
     * @notice Set admin
     * @param newAdmin Addres of new admin
     */
    function setAdmin(address newAdmin) external onlyOwner {
        admin = newAdmin;
        emit SetAdmin(newAdmin);
    }

    /**
     * @notice Transfer amount of token from Storage to Logic contract token - address of the token
     * @param amount Amount of token
     * @param token Address of token
     */
    function takeTokenFromStorage(uint256 amount, address token) external onlyOwnerAndAdmin {
        IStorage(_storage).takeToken(amount, token);
    }

    /**
     * @notice Transfer amount of token from Logic to Storage contract token - address of token
     * @param amount Amount of token
     * @param token Address of token
     */
    function returnTokenToStorage(uint256 amount, address token) external onlyOwnerAndAdmin {
        IStorage(_storage).returnToken(amount, token);
    }

    /**
     * @notice Distribution amount of blid to depositors.
     * @param amount Amount of BLID
     */
    function addEarnToStorage(uint256 amount) external onlyOwnerAndAdmin {
        IERC20(blid).safeTransfer(expenseAddress, (amount * 3) / 100);
        IStorage(_storage).addEarn((amount * 97) / 100);
    }

    /**
     * @notice Enter into a list of markets(address of VTokens) - it is not an
     * error to enter the same market more than once.
     * @param vTokens The addresses of the vToken markets to enter.
     * @return For each market, returns an error code indicating whether or not it was entered.
     * Each is 0 on success, otherwise an Error code
     */
    function enterMarkets(address[] calldata vTokens) external onlyOwnerAndAdmin returns (uint256[] memory) {
        return IDistribution(venusController).enterMarkets(vTokens);
    }

    /**
     * @notice Every Venus user accrues XVS for each block
     * they are supplying to or borrowing from the protocol.
     * @param vTokens The addresses of the vToken markets to enter.
     */
    function claimVenus(address[] calldata vTokens) external onlyOwnerAndAdmin {
        IDistribution(venusController).claimVenus(address(this), vTokens);
    }

    /**
     * @notice Stake token and mint VToken
     * @param vToken: that mint Vtokens to this contract
     * @param mintAmount: The amount of the asset to be supplied, in units of the underlying asset.
     * @return 0 on success, otherwise an Error code
     */
    function mint(address vToken, uint256 mintAmount)
        external
        isUsedVToken(vToken)
        onlyOwnerAndAdmin
        returns (uint256)
    {
        if (vToken == vBNB) {
            IVToken(vToken).mint{ value: mintAmount }();
        }
        return IVToken(vToken).mint(mintAmount);
    }

    /**
     * @notice The borrow function transfers an asset from the protocol to the user and creates a
     * borrow balance which begins accumulating interest based on the Borrow Rate for the asset.
     * The amount borrowed must be less than the user's Account Liquidity and the market's
     * available liquidity.
     * @param vToken: that mint Vtokens to this contract
     * @param borrowAmount: The amount of underlying to be borrow.
     * @return 0 on success, otherwise an Error code
     */
    function borrow(address vToken, uint256 borrowAmount)
        external
        payable
        isUsedVToken(vToken)
        onlyOwnerAndAdmin
        returns (uint256)
    {
        return IVToken(vToken).borrow(borrowAmount);
    }

    /**
     * @notice The repay function transfers an asset into the protocol, reducing the user's borrow balance.
     * @param vToken: that mint Vtokens to this contract
     * @param repayAmount: The amount of the underlying borrowed asset to be repaid.
     * A value of -1 (i.e. 2256 - 1) can be used to repay the full amount.
     * @return 0 on success, otherwise an Error code
     */
    function repayBorrow(address vToken, uint256 repayAmount)
        external
        isUsedVToken(vToken)
        onlyOwnerAndAdmin
        returns (uint256)
    {
        if (vToken == vBNB) {
            IVToken(vToken).repayBorrow{ value: repayAmount }();
            return 0;
        }
        return IVToken(vToken).repayBorrow(repayAmount);
    }

    /**
     * @notice The redeem underlying function converts vTokens into a specified quantity of the
     * underlying asset, and returns them to the user.
     * The amount of vTokens redeemed is equal to the quantity of underlying tokens received,
     * divided by the current Exchange Rate.
     * The amount redeemed must be less than the user's Account Liquidity and the market's
     * available liquidity.
     * @param vToken: that mint Vtokens to this contract
     * @param redeemAmount: The amount of underlying to be redeemed.
     * @return 0 on success, otherwise an Error code
     */
    function redeemUnderlying(address vToken, uint256 redeemAmount)
        external
        isUsedVToken(vToken)
        onlyOwnerAndAdmin
        returns (uint256)
    {
        return IVToken(vToken).redeemUnderlying(redeemAmount);
    }

    /**
     * @notice Adds liquidity to a BEP20⇄BEP20 pool.
     * @param swap Address of swap router
     * @param tokenA The contract address of one token from your liquidity pair.
     * @param tokenB The contract address of the other token from your liquidity pair.
     * @param amountADesired The amount of tokenA you'd like to provide as liquidity.
     * @param amountBDesired The amount of tokenA you'd like to provide as liquidity.
     * @param amountAMin The minimum amount of tokenA to provide (slippage impact).
     * @param amountBMin The minimum amount of tokenB to provide (slippage impact).
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function addLiquidity(
        address swap,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    )
        external
        isUsedSwap(swap)
        onlyOwnerAndAdmin
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        (amountADesired, amountBDesired, amountAMin) = IPancakeRouter01(swap).addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            address(this),
            deadline
        );

        return (amountADesired, amountBDesired, amountAMin);
    }

    /**
     * @notice Removes liquidity from a BEP20⇄BEP20 pool.
     * @param swap Address of swap router
     * @param tokenA The contract address of one token from your liquidity pair.
     * @param tokenB The contract address of the other token from your liquidity pair.
     * @param liquidity The amount of LP Tokens to remove.
     * @param amountAMin he minimum amount of tokenA to provide (slippage impact).
     * @param amountBMin The minimum amount of tokenB to provide (slippage impact).
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function removeLiquidity(
        address swap,
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline
    ) external onlyOwnerAndAdmin isUsedSwap(swap) returns (uint256 amountA, uint256 amountB) {
        (amountAMin, amountBMin) = IPancakeRouter01(swap).removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            amountAMin,
            amountBMin,
            address(this),
            deadline
        );

        return (amountAMin, amountBMin);
    }

    /**
     * @notice Receive an as many output tokens as possible for an exact amount of input tokens.
     * @param swap Address of swap router
     * @param amountIn TPayable amount of input tokens.
     * @param amountOutMin The minimum amount tokens to receive.
     * @param path (address[]) An array of token addresses. path.length must be >= 2.
     * Pools for each consecutive pair of addresses must exist and have liquidity.
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function swapExactTokensForTokens(
        address swap,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external isUsedSwap(swap) onlyOwnerAndAdmin returns (uint256[] memory amounts) {
        return
            IPancakeRouter01(swap).swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                path,
                address(this),
                deadline
            );
    }

    /**
     * @notice Receive an exact amount of output tokens for as few input tokens as possible.
     * @param swap Address of swap router
     * @param amountOut Payable amount of input tokens.
     * @param amountInMax The minimum amount tokens to input.
     * @param path (address[]) An array of token addresses. path.length must be >= 2.
     * Pools for each consecutive pair of addresses must exist and have liquidity.
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function swapTokensForExactTokens(
        address swap,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        uint256 deadline
    ) external onlyOwnerAndAdmin isUsedSwap(swap) returns (uint256[] memory amounts) {
        return
            IPancakeRouter01(swap).swapTokensForExactTokens(
                amountOut,
                amountInMax,
                path,
                address(this),
                deadline
            );
    }

    /**
     * @notice Adds liquidity to a BEP20⇄WBNB pool.
     * @param swap Address of swap router
     * @param token The contract address of one token from your liquidity pair.
     * @param amountTokenDesired The amount of the token you'd like to provide as liquidity.
     * @param amountETHDesired The minimum amount of the token to provide (slippage impact).
     * @param amountTokenMin The minimum amount of token to provide (slippage impact).
     * @param amountETHMin The minimum amount of BNB to provide (slippage impact).
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function addLiquidityETH(
        address swap,
        address token,
        uint256 amountTokenDesired,
        uint256 amountETHDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        uint256 deadline
    )
        external
        isUsedSwap(swap)
        onlyOwnerAndAdmin
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        )
    {
        (amountETHDesired, amountTokenMin, amountETHMin) = IPancakeRouter01(swap).addLiquidityETH{
            value: amountETHDesired
        }(token, amountTokenDesired, amountTokenMin, amountETHMin, address(this), deadline);

        return (amountETHDesired, amountTokenMin, amountETHMin);
    }

    /**
     * @notice Removes liquidity from a BEP20⇄WBNB pool.
     * @param swap Address of swap router
     * @param token The contract address of one token from your liquidity pair.
     * @param liquidity The amount of LP Tokens to remove.
     * @param amountTokenMin The minimum amount of the token to remove (slippage impact).
     * @param amountETHMin The minimum amount of BNB to remove (slippage impact).
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function removeLiquidityETH(
        address swap,
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        uint256 deadline
    ) external payable isUsedSwap(swap) onlyOwnerAndAdmin returns (uint256 amountToken, uint256 amountETH) {
        (deadline, amountETHMin) = IPancakeRouter01(swap).removeLiquidityETH(
            token,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );

        return (deadline, amountETHMin);
    }

    /**
     * @notice Receive as many output tokens as possible for an exact amount of BNB.
     * @param swap Address of swap router
     * @param amountETH Payable BNB amount.
     * @param amountOutMin 	The minimum amount tokens to input.
     * @param path (address[]) An array of token addresses. path.length must be >= 2.
     * Pools for each consecutive pair of addresses must exist and have liquidity.
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function swapExactETHForTokens(
        address swap,
        uint256 amountETH,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external isUsedSwap(swap) onlyOwnerAndAdmin returns (uint256[] memory amounts) {
        return
            IPancakeRouter01(swap).swapExactETHForTokens{ value: amountETH }(
                amountOutMin,
                path,
                address(this),
                deadline
            );
    }

    /**
     * @notice Receive an exact amount of output tokens for as few input tokens as possible.
     * @param swap Address of swap router
     * @param amountOut Payable BNB amount.
     * @param amountInMax The minimum amount tokens to input.
     * @param path (address[]) An array of token addresses. path.length must be >= 2.
     * Pools for each consecutive pair of addresses must exist and have liquidity.
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function swapTokensForExactETH(
        address swap,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        uint256 deadline
    ) external payable isUsedSwap(swap) onlyOwnerAndAdmin returns (uint256[] memory amounts) {
        return
            IPancakeRouter01(swap).swapTokensForExactETH(
                amountOut,
                amountInMax,
                path,
                address(this),
                deadline
            );
    }

    /**
     * @notice Receive as much BNB as possible for an exact amount of input tokens.
     * @param swap Address of swap router
     * @param amountIn Payable amount of input tokens.
     * @param amountOutMin The maximum amount tokens to input.
     * @param path (address[]) An array of token addresses. path.length must be >= 2.
     * Pools for each consecutive pair of addresses must exist and have liquidity.
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function swapExactTokensForETH(
        address swap,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external payable isUsedSwap(swap) onlyOwnerAndAdmin returns (uint256[] memory amounts) {
        return
            IPancakeRouter01(swap).swapExactTokensForETH(
                amountIn,
                amountOutMin,
                path,
                address(this),
                deadline
            );
    }

    /**
     * @notice Receive an exact amount of output tokens for as little BNB as possible.
     * @param swap Address of swap router
     * @param amountOut The amount tokens to receive.
     * @param amountETH Payable BNB amount.
     * @param path (address[]) An array of token addresses. path.length must be >= 2.
     * Pools for each consecutive pair of addresses must exist and have liquidity.
     * @param deadline Unix timestamp deadline by which the transaction must confirm.
     */
    function swapETHForExactTokens(
        address swap,
        uint256 amountETH,
        uint256 amountOut,
        address[] calldata path,
        uint256 deadline
    ) external isUsedSwap(swap) onlyOwnerAndAdmin returns (uint256[] memory amounts) {
        return
            IPancakeRouter01(swap).swapETHForExactTokens{ value: amountETH }(
                amountOut,
                path,
                address(this),
                deadline
            );
    }

    /**
     * @notice Deposit LP tokens to Master
     * @param swapMaster Address of swap master(Main staking contract)
     * @param _pid pool id
     * @param _amount amount of lp token
     */
    function deposit(
        address swapMaster,
        uint256 _pid,
        uint256 _amount
    ) external isUsedMaster(swapMaster) onlyOwnerAndAdmin {
        IMasterChef(swapMaster).deposit(_pid, _amount);
    }

    /**
     * @notice Withdraw LP tokens from Master
     * @param swapMaster Address of swap master(Main staking contract)
     * @param _pid pool id
     * @param _amount amount of lp token
     */
    function withdraw(
        address swapMaster,
        uint256 _pid,
        uint256 _amount
    ) external isUsedMaster(swapMaster) onlyOwnerAndAdmin {
        IMasterChef(swapMaster).withdraw(_pid, _amount);
    }

    /**
     * @notice Stake BANANA/Cake tokens to STAKING.
     * @param swapMaster Address of swap master(Main staking contract)
     * @param _amount amount of lp token
     */
    function enterStaking(address swapMaster, uint256 _amount)
        external
        isUsedMaster(swapMaster)
        onlyOwnerAndAdmin
    {
        IMasterChef(swapMaster).enterStaking(_amount);
    }

    /**
     * @notice Withdraw BANANA/Cake tokens from STAKING.
     * @param swapMaster Address of swap master(Main staking contract)
     * @param _amount amount of lp token
     */
    function leaveStaking(address swapMaster, uint256 _amount)
        external
        isUsedMaster(swapMaster)
        onlyOwnerAndAdmin
    {
        IMasterChef(swapMaster).leaveStaking(_amount);
    }

    /**
     * @notice Add reserve staked lp token to end list
     * @param reserveLiquidity Data is about staked lp in farm
     */
    function addReserveLiquidity(ReserveLiquidity memory reserveLiquidity) external onlyOwnerAndAdmin {
        reserves.push(reserveLiquidity);
    }

    /**
     * @notice Delete last ReserveLiquidity from list of ReserveLiquidity
     */
    function deleteLastReserveLiquidity() external onlyOwnerAndAdmin {
        reserves.pop();
    }

    /**
     * @notice Return count reserves staked lp tokens for return users their tokens.
     */
    function getReservesCount() external view returns (uint256) {
        return reserves.length;
    }

    /**
     * @notice Return reserves staked lp tokens for return user their tokens. return ReserveLiquidity
     */
    function getReserve(uint256 id) external view returns (ReserveLiquidity memory) {
        return reserves[id];
    }

    /*** Prive Function ***/

    /**
     * @notice Repay borrow when in farms  erc20 and BNB
     */
    function repayBorrowBNBandToken(
        address swap,
        address tokenB,
        address VTokenA,
        address VTokenB,
        uint256 lpAmount
    ) private {
        (uint256 amountToken, uint256 amountETH) = IPancakeRouter01(swap).removeLiquidityETH(
            tokenB,
            lpAmount,
            0,
            0,
            address(this),
            block.timestamp + 1 days
        );
        {
            uint256 totalBorrow = IVToken(VTokenA).borrowBalanceCurrent(address(this));
            if (totalBorrow >= amountETH) {
                IVToken(VTokenA).repayBorrow{ value: amountETH }();
            } else {
                IVToken(VTokenA).repayBorrow{ value: totalBorrow }();
            }

            totalBorrow = IVToken(VTokenB).borrowBalanceCurrent(address(this));
            if (totalBorrow >= amountToken) {
                IVToken(VTokenB).repayBorrow(amountToken);
            } else {
                IVToken(VTokenB).repayBorrow(totalBorrow);
            }
        }
    }

    /**
     * @notice Repay borrow when in farms only erc20
     */
    function repayBorrowOnlyTokens(
        address swap,
        address tokenA,
        address tokenB,
        address VTokenA,
        address VTokenB,
        uint256 lpAmount
    ) private {
        (uint256 amountA, uint256 amountB) = IPancakeRouter01(swap).removeLiquidity(
            tokenA,
            tokenB,
            lpAmount,
            0,
            0,
            address(this),
            block.timestamp + 1 days
        );
        {
            uint256 totalBorrow = IVToken(VTokenA).borrowBalanceCurrent(address(this));
            if (totalBorrow >= amountA) {
                IVToken(VTokenA).repayBorrow(amountA);
            } else {
                IVToken(VTokenA).repayBorrow(totalBorrow);
            }

            totalBorrow = IVToken(VTokenB).borrowBalanceCurrent(address(this));
            if (totalBorrow >= amountB) {
                IVToken(VTokenB).repayBorrow(amountB);
            } else {
                IVToken(VTokenB).repayBorrow(totalBorrow);
            }
        }
    }

    /**
     * @notice Withdraw lp token from farms and repay borrow
     */
    function withdrawAndRepay(ReserveLiquidity memory reserve, uint256 lpAmount) private {
        IMasterChef(reserve.swapMaster).withdraw(reserve.poolID, lpAmount);
        if (reserve.tokenA == address(0) || reserve.tokenB == address(0)) {
            //if tokenA is BNB
            if (reserve.tokenA == address(0)) {
                repayBorrowBNBandToken(
                    reserve.swap,
                    reserve.tokenB,
                    reserve.vTokenA,
                    reserve.vTokenB,
                    lpAmount
                );
            }
            //if tokenB is BNB
            else {
                repayBorrowBNBandToken(
                    reserve.swap,
                    reserve.tokenA,
                    reserve.vTokenB,
                    reserve.vTokenA,
                    lpAmount
                );
            }
        }
        //if token A and B is not BNB
        else {
            repayBorrowOnlyTokens(
                reserve.swap,
                reserve.tokenA,
                reserve.tokenB,
                reserve.vTokenA,
                reserve.vTokenB,
                lpAmount
            );
        }
    }

    /*** Prive View Function ***/
    /**
     * @notice Convert Lp Token To Token
     */
    function getPriceFromLpToToken(
        address lpToken,
        uint256 value,
        address token,
        address swap,
        address[] memory path
    ) private view returns (uint256) {
        //make price returned not affected by slippage rate
        uint256 totalSupply = IERC20(lpToken).totalSupply();
        address token0 = IPancakePair(lpToken).token0();
        uint256 totalTokenAmount = IERC20(token0).balanceOf(lpToken) * (2);
        uint256 amountIn = (value * totalTokenAmount) / (totalSupply);

        if (amountIn == 0 || token0 == token) {
            return amountIn;
        }

        uint256[] memory price = IPancakeRouter01(swap).getAmountsOut(amountIn, path);
        return price[price.length - 1];
    }

    /**
     * @notice Convert Token To Lp Token
     */
    function getPriceFromTokenToLp(
        address lpToken,
        uint256 value,
        address token,
        address swap,
        address[] memory path
    ) private view returns (uint256) {
        //make price returned not affected by slippage rate
        uint256 totalSupply = IERC20(lpToken).totalSupply();
        address token0 = IPancakePair(lpToken).token0();
        uint256 totalTokenAmount = IERC20(token0).balanceOf(lpToken);

        if (token0 == token) {
            return (value * (totalSupply)) / (totalTokenAmount) / 2;
        }

        uint256[] memory price = IPancakeRouter01(swap).getAmountsOut((1 gwei), path);
        return (value * (totalSupply)) / ((price[price.length - 1] * 2 * totalTokenAmount) / (1 gwei));
    }

    /**
     * @notice FindPath for swap router
     */
    function findPath(uint256 id, address token) private view returns (address[] memory path) {
        ReserveLiquidity memory reserve = reserves[id];
        uint256 length = reserve.path.length;

        for (uint256 i = 0; i < length; i++) {
            if (reserve.path[i][reserve.path[i].length - 1] == token) {
                return reserve.path[i];
            }
        }
    }
}
