// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "./interfaces/external/IWETH9.sol";
import "./utils/ReentrancyGuard.sol";
import './libraries/TransferHelper.sol';
import "./libraries/SqrtPriceMath.sol";
import "./base/ERC20Permit.sol";
import "./libraries/Babylonian.sol";
import "./libraries/PoolActions.sol";
import "./interfaces/IOptimizerStrategy.sol";
import "./interfaces/IPopsicleV3Optimizer.sol";

/// @title PopsicleV3 Optimizer is a yield enchancement v3 contract
/// @dev PopsicleV3 Optimizer is a Uniswap V3 yield enchancement contract which acts as
/// intermediary between the user who wants to provide liquidity to specific pools
/// and earn fees from such actions. The contract ensures that user position is in 
/// range and earns maximum amount of fees available at current liquidity utilization
/// rate. 
contract PopsicleV3Optimizer is ERC20Permit, ReentrancyGuard, IPopsicleV3Optimizer {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for uint160;
    using LowGasSafeMath for uint128;
    using UnsafeMath for uint256;
    using SafeCast for uint256;
    using PoolVariables for IUniswapV3Pool;
    using PoolActions for IUniswapV3Pool;
    
    //Any data passed through by the caller via the IUniswapV3PoolActions#mint call
    struct MintCallbackData {
        address payer;
    }
    //Any data passed through by the caller via the IUniswapV3PoolActions#swap call
    struct SwapCallbackData {
        bool zeroForOne;
    }

    /// @notice Emitted when user adds liquidity
    /// @param sender The address that minted the liquidity
    /// @param share The amount of share of liquidity added by the user to position
    /// @param amount0 How much token0 was required for the added liquidity
    /// @param amount1 How much token1 was required for the added liquidity
    event Deposit(
        address indexed sender,
        uint256 share,
        uint256 amount0,
        uint256 amount1
    );
    
    /// @notice Emitted when user withdraws liquidity
    /// @param sender The address that minted the liquidity
    /// @param shares of liquidity withdrawn by the user from the position
    /// @param amount0 How much token0 was required for the added liquidity
    /// @param amount1 How much token1 was required for the added liquidity
    /// @param fee0 Amount of fees of token0 collected by user during last period
    /// @param fee1 Amount of fees of token1 collected by user during last period
    event Withdraw(
        address indexed sender,
        uint256 shares,
        uint256 amount0,
        uint256 amount1,
        uint256 fee0,
        uint256 fee1
    );
    
    /// @notice Emitted when fees was collected from the pool
    /// @param feesFromPool0 Total amount of fees collected in terms of token 0
    /// @param feesFromPool1 Total amount of fees collected in terms of token 1
    /// @param usersFees0 Total amount of fees collected by users in terms of token 0
    /// @param usersFees1 Total amount of fees collected by users in terms of token 1
    event CollectFees(
        uint256 feesFromPool0,
        uint256 feesFromPool1,
        uint256 usersFees0,
        uint256 usersFees1
    );

    /// @notice Emitted when fees was compuonded to the pool
    /// @param amount0 Total amount of fees compounded in terms of token 0
    /// @param amount1 Total amount of fees compounded in terms of token 1
    event CompoundFees(
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when PopsicleV3 Optimizer changes the position in the pool
    /// @param tickLower Lower price tick of the positon
    /// @param tickUpper Upper price tick of the position
    /// @param amount0 Amount of token 0 deposited to the position
    /// @param amount1 Amount of token 1 deposited to the position
    event Rerange(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    );
    
    /// @notice Emitted when user collects his fee share
    /// @param sender User address
    /// @param fees0 Exact amount of fees claimed by the users in terms of token 0 
    /// @param fees1 Exact amount of fees claimed by the users in terms of token 1
    event RewardPaid(
        address indexed sender,
        uint256 fees0,
        uint256 fees1
    );
    
    /// @notice Shows current Optimizer's balances
    /// @param totalAmount0 Current token0 Optimizer's balance
    /// @param totalAmount1 Current token1 Optimizer's balance
    event Snapshot(uint256 totalAmount0, uint256 totalAmount1);

    event TransferGovernance(address indexed previousGovernance, address indexed newGovernance);
    
    /// @notice Prevents calls from users
    modifier onlyGovernance {
        require(msg.sender == governance, "OG");
        _;
    }

    /// @inheritdoc IPopsicleV3Optimizer
    address public immutable override token0;
    /// @inheritdoc IPopsicleV3Optimizer
    address public immutable override token1;
    // WETH address
    address public constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // @inheritdoc IPopsicleV3Optimizer
    int24 public immutable override tickSpacing;
    uint24 constant GLOBAL_DIVISIONER = 1e6; // for basis point (0.0001%)
    //The protocol's fee in hundredths of a bip, i.e. 1e-6
    uint24 constant protocolFee = 1e5; 

    mapping (address => bool) private _operatorApproved;

    // @inheritdoc IPopsicleV3Optimizer
    IUniswapV3Pool public override pool;
    // Accrued protocol fees in terms of token0
    uint256 public protocolFees0;
    // Accrued protocol fees in terms of token1
    uint256 public protocolFees1;
    // Total lifetime accrued fees in terms of token0
    uint256 public totalFees0;
    // Total lifetime accrued fees in terms of token1
    uint256 public totalFees1;
    
    // Address of the Optimizer's owner
    address public governance;
    // Pending to claim ownership address
    address public pendingGovernance;
    //PopsicleV3 Optimizer settings address
    address public strategy;
    // Current tick lower of Optimizer pool position
    int24 public override tickLower;
    // Current tick higher of Optimizer pool position
    int24 public override tickUpper;
    // Checks if Optimizer is initialized
    bool public initialized;

    bool private _paused = false;
    
    /**
     * @dev After deploying, strategy can be set via `setStrategy()`
     * @param _pool Underlying Uniswap V3 pool with fee = 3000
     * @param _strategy Underlying Optimizer Strategy for Optimizer settings
     */
     constructor(
        address _pool,
        address _strategy
    ) ERC20("Popsicle LP V3 USDT/WETH", "PLP") ERC20Permit("Popsicle LP V3 USDT/WETH") {
        pool = IUniswapV3Pool(_pool);
        strategy = _strategy;
        token0 = pool.token0();
        token1 = pool.token1();
        tickSpacing = pool.tickSpacing();
        governance = msg.sender;
        _operatorApproved[msg.sender] = true;
    }
    //initialize strategy
    function init() external onlyGovernance {
        require(!initialized, "F");
        initialized = true;
        int24 baseThreshold = tickSpacing * IOptimizerStrategy(strategy).tickRangeMultiplier();
        ( , int24 currentTick, , , , , ) = pool.slot0();
        int24 tickFloor = PoolVariables.floor(currentTick, tickSpacing);
        
        tickLower = tickFloor - baseThreshold;
        tickUpper = tickFloor + baseThreshold;
        PoolVariables.checkRange(tickLower, tickUpper); //check ticks also for overflow/underflow
    }
    
    /// @inheritdoc IPopsicleV3Optimizer
     function deposit(
        uint256 amount0Desired,
        uint256 amount1Desired,
        address to
    )
        external
        payable
        override
        nonReentrant
        checkDeviation
        whenNotPaused
        returns (
            uint256 shares,
            uint256 amount0,
            uint256 amount1
        )
    {
        require(amount0Desired > 0 && amount1Desired > 0, "ANV");
        _earnFees();
        _compoundFees(); // prevent user drains outher 
        uint128 protocolLiquidity = pool.liquidityForAmounts(protocolFees0, protocolFees1, tickLower, tickUpper);
        uint128 liquidityLast = pool.positionLiquidity(tickLower, tickUpper).sub128(protocolLiquidity); // prevent protocol drains users 
        // compute the liquidity amount
        uint128 liquidity = pool.liquidityForAmounts(amount0Desired, amount1Desired, tickLower, tickUpper);
        
        (amount0, amount1) = pool.mint(
            address(this),
            tickLower,
            tickUpper,
            liquidity,
            abi.encode(MintCallbackData({payer: msg.sender})));
        
        
        shares = _calcShare(liquidity, liquidityLast);

        _mint(to, shares);
        require(IOptimizerStrategy(strategy).maxTotalSupply() >= totalSupply(), "MTS");
        refundETH();
        emit Deposit(msg.sender, shares, amount0, amount1);
    }
    
    /// @inheritdoc IPopsicleV3Optimizer
    function withdraw(
        uint256 shares,
        address to
    ) 
        external
        override
        nonReentrant
        checkDeviation
        whenNotPaused
        returns (
            uint256 amount0,
            uint256 amount1
        )
    {
        require(shares > 0, "S");
        require(to != address(0), "WZA");
        (uint256 collect0, uint256 collect1) = _earnFees();
        //Get Liquidity for ProtocolFee
        uint128 protocolLiquidity = pool.liquidityForAmounts(protocolFees0, protocolFees1, tickLower, tickUpper);
        
        (amount0, amount1) = pool.burnLiquidityShare(tickLower, tickUpper, totalSupply(), shares,  to, protocolLiquidity);
        
        uint256 userFees0 = collect0.mul(shares) / totalSupply();
        uint256 userFees1 = collect1.mul(shares) / totalSupply();
        // Burn shares
        _burn(msg.sender, shares);
        if (userFees0 > 0) pay(token0, address(this), to, userFees0);
        if (userFees1 > 0) pay(token1, address(this), to, userFees1);
        _compoundFees();
        emit Withdraw(msg.sender, shares, amount0, amount1, userFees0, userFees1);
    }
    
    /// @inheritdoc IPopsicleV3Optimizer
    function rerange() external payable override nonReentrant checkDeviation {
        require(_operatorApproved[msg.sender], "ONA");
        _earnFees();
        //Burn all liquidity from pool to rerange for Optimizer's balances.
        pool.burnAllLiquidity(tickLower, tickUpper);
        

        // Emit snapshot to record balances
        uint256 balance0 = _balance0();
        uint256 balance1 = _balance1();
        emit Snapshot(balance0, balance1);

        int24 baseThreshold = tickSpacing * IOptimizerStrategy(strategy).tickRangeMultiplier();

        //Get exact ticks depending on Optimizer's balances
        (tickLower, tickUpper) = pool.getPositionTicks(balance0, balance1, baseThreshold, tickSpacing);

        //Get Liquidity for Optimizer's balances
        uint128 liquidity = pool.liquidityForAmounts(balance0, balance1, tickLower, tickUpper);
        
        // Add liquidity to the pool
        (uint256 amount0, uint256 amount1) = pool.mint(
            address(this),
            tickLower,
            tickUpper,
            liquidity,
            abi.encode(MintCallbackData({payer: address(this)})));
        block.coinbase.transfer(msg.value); //pay to miner. more info https://github.com/flashbots/pm
        emit Rerange(tickLower, tickUpper, amount0, amount1);
    }

    /// @inheritdoc IPopsicleV3Optimizer
    function rebalance() external payable override nonReentrant checkDeviation {
        require(_operatorApproved[msg.sender], "ONA");
        _earnFees();
        //Burn all liquidity from pool to rerange for Optimizer's balances.
        pool.burnAllLiquidity(tickLower, tickUpper);
        
        //Calc base ticks
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();
        PoolVariables.Info memory cache;
        int24 baseThreshold = tickSpacing * IOptimizerStrategy(strategy).tickRangeMultiplier();
        (cache.tickLower, cache.tickUpper) = PoolVariables.baseTicks(currentTick, baseThreshold, tickSpacing);
        
        cache.amount0Desired = _balance0();
        cache.amount1Desired = _balance1();
        emit Snapshot(cache.amount0Desired, cache.amount1Desired);
        // Calc liquidity for base ticks
        cache.liquidity = pool.liquidityForAmounts(cache.amount0Desired, cache.amount1Desired, cache.tickLower, cache.tickUpper);

        // Get exact amounts for base ticks
        (cache.amount0, cache.amount1) = pool.amountsForLiquidity(cache.liquidity, cache.tickLower, cache.tickUpper);

        // Get imbalanced token
        bool zeroForOne = PoolVariables.amountsDirection(cache.amount0Desired, cache.amount1Desired, cache.amount0, cache.amount1);
        // Calculate the amount of imbalanced token that should be swapped. Calculations strive to achieve one to one ratio
        int256 amountSpecified = 
            zeroForOne
                ? int256(cache.amount0Desired.sub(cache.amount0).unsafeDiv(2))
                : int256(cache.amount1Desired.sub(cache.amount1).unsafeDiv(2)); // always positive. "overflow" safe convertion cuz we are dividing by 2

        // Calculate Price limit depending on price impact
        uint160 exactSqrtPriceImpact = sqrtPriceX96.mul160(IOptimizerStrategy(strategy).priceImpactPercentage() / 2) / GLOBAL_DIVISIONER;
        uint160 sqrtPriceLimitX96 = zeroForOne ?  sqrtPriceX96.sub160(exactSqrtPriceImpact) : sqrtPriceX96.add160(exactSqrtPriceImpact);

        //Swap imbalanced token as long as we haven't used the entire amountSpecified and haven't reached the price limit
        pool.swap(
            address(this),
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            abi.encode(SwapCallbackData({zeroForOne: zeroForOne}))
        );


        (sqrtPriceX96, currentTick, , , , , ) = pool.slot0();

        // Emit snapshot to record balances
        cache.amount0Desired = _balance0();
        cache.amount1Desired = _balance1();
        emit Snapshot(cache.amount0Desired, cache.amount1Desired);
        //Get exact ticks depending on Optimizer's new balances
        (tickLower, tickUpper) = pool.getPositionTicks(cache.amount0Desired, cache.amount1Desired, baseThreshold, tickSpacing);

        cache.liquidity = pool.liquidityForAmounts(cache.amount0Desired, cache.amount1Desired, tickLower, tickUpper);

        // Add liquidity to the pool
        (cache.amount0, cache.amount1) = pool.mint(
            address(this),
            tickLower,
            tickUpper,
            cache.liquidity,
            abi.encode(MintCallbackData({payer: address(this)})));

        block.coinbase.transfer(msg.value); //pay to miner. more info https://github.com/flashbots/pm

        emit Rerange(tickLower, tickUpper, cache.amount0, cache.amount1);
    }

    // Calcs user share depending on deposited amounts
    function _calcShare(uint128 liquidity, uint128 liquidityLast)
        internal
        view
        returns (
            uint256 shares
        )
    {
        shares = totalSupply() == 0 ? uint256(liquidity) : uint256(liquidity).mul(totalSupply()).unsafeDiv(uint256(liquidityLast));
    }
    
    /// @dev Amount of token0 held as unused balance.
    function _balance0() internal view returns (uint256) {
        return IERC20(token0).balanceOf(address(this));
    }

    /// @dev Amount of token1 held as unused balance.
    function _balance1() internal view returns (uint256) {
        return IERC20(token1).balanceOf(address(this));
    }
    
    /// @dev collects fees from the pool
    function _earnFees() internal returns (uint256 collect0, uint256 collect1) {
        uint liquidity = pool.positionLiquidity(tickLower, tickUpper);
        if (liquidity == 0) return (0,0); // we can't poke when liquidity is zero
         // Do zero-burns to poke the Uniswap pools so earned fees are updated
        pool.burn(tickLower, tickUpper, 0);
        
        (collect0, collect1) =
            pool.collect(
                address(this),
                tickLower,
                tickUpper,
                type(uint128).max,
                type(uint128).max
            );

        // Calculate protocol's fees
        uint256 earnedProtocolFees0 = collect0.mul(protocolFee).unsafeDiv(GLOBAL_DIVISIONER);
        uint256 earnedProtocolFees1 = collect1.mul(protocolFee).unsafeDiv(GLOBAL_DIVISIONER);
        protocolFees0 = protocolFees0.add(earnedProtocolFees0);
        protocolFees1 = protocolFees1.add(earnedProtocolFees1);
        totalFees0 = totalFees0.add(collect0);
        totalFees1 = totalFees1.add(collect1);
        collect0 = collect0.sub(earnedProtocolFees0);
        collect1 = collect1.sub(earnedProtocolFees1);
        emit CollectFees(collect0, collect1, totalFees0, totalFees1);
    }

    function _compoundFees() internal returns (uint256 amount0, uint256 amount1){
        uint256 balance0 = _balance0();
        uint256 balance1 = _balance1();

        emit Snapshot(balance0, balance1);

        //Get Liquidity for Optimizer's balances
        uint128 liquidity = pool.liquidityForAmounts(balance0, balance1, tickLower, tickUpper);
        
        // Add liquidity to the pool
        if (liquidity > 0)
        {
            (amount0, amount1) = pool.mint(
                address(this),
                tickLower,
                tickUpper,
                liquidity,
                abi.encode(MintCallbackData({payer: address(this)})));
            emit CompoundFees(amount0, amount1);
        }
    }

    /// @notice Returns current Optimizer's position in pool
    function position() external view returns (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1) {
        bytes32 positionKey = PositionKey.compute(address(this), tickLower, tickUpper);
        (liquidity, feeGrowthInside0LastX128, feeGrowthInside1LastX128, tokensOwed0, tokensOwed1) = pool.positions(positionKey);
    }
    
    /// @notice Pull in tokens from sender. Called to `msg.sender` after minting liquidity to a position from IUniswapV3Pool#mint.
    /// @dev In the implementation you must pay to the pool for the minted liquidity.
    /// @param amount0 The amount of token0 due to the pool for the minted liquidity
    /// @param amount1 The amount of token1 due to the pool for the minted liquidity
    /// @param data Any data passed through by the caller via the IUniswapV3PoolActions#mint call
    function uniswapV3MintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        require(msg.sender == address(pool), "FP");
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        if (amount0 > 0) pay(token0, decoded.payer, msg.sender, amount0);
        if (amount1 > 0) pay(token1, decoded.payer, msg.sender, amount1);
    }

    /// @notice Called to `msg.sender` after minting swaping from IUniswapV3Pool#swap.
    /// @dev In the implementation you must pay to the pool for swap.
    /// @param amount0 The amount of token0 due to the pool for the swap
    /// @param amount1 The amount of token1 due to the pool for the swap
    /// @param _data Any data passed through by the caller via the IUniswapV3PoolActions#swap call
    function uniswapV3SwapCallback(
        int256 amount0,
        int256 amount1,
        bytes calldata _data
    ) external {
        require(msg.sender == address(pool), "FP");
        require(amount0 > 0 || amount1 > 0, "LEZ"); // swaps entirely within 0-liquidity regions are not supported
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        bool zeroForOne = data.zeroForOne;

        if (zeroForOne) pay(token0, address(this), msg.sender, uint256(amount0)); 
        else pay(token1, address(this), msg.sender, uint256(amount1));
    }

    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The entity that will receive payment
    /// @param value The amount to pay
    function pay(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token == weth && address(this).balance >= value) {
            // pay with WETH9
            IWETH9(weth).deposit{value: value}(); // wrap only what is needed to pay
            IWETH9(weth).transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }
    
    /**
     * @notice Used to withdraw accumulated protocol fees.
     */
    function collectProtocolFees(
        uint256 amount0,
        uint256 amount1
    ) external nonReentrant onlyGovernance {
        require(protocolFees0 >= amount0, "A0F");
        require(protocolFees1 >= amount1, "A1F");
        _earnFees();
        uint256 balance0 = _balance0();
        uint256 balance1 = _balance1();
        
        if (balance0 >= amount0 && balance1 >= amount1)
        {
            if (amount0 > 0) pay(token0, address(this), msg.sender, amount0);
            if (amount1 > 0) pay(token1, address(this), msg.sender, amount1);
        }
        else
        {
            uint128 liquidity = pool.liquidityForAmounts(amount0, amount1, tickLower, tickUpper);
            (amount0, amount1) = pool.burnExactLiquidity(tickLower, tickUpper, liquidity, msg.sender);
        
        }
        
        protocolFees0 = protocolFees0.sub(amount0);
        protocolFees1 = protocolFees1.sub(amount1);
        _compoundFees();
        emit RewardPaid(msg.sender, amount0, amount1);
    }

    // Function modifier that checks if price has not moved a lot recently.
    // This mitigates price manipulation during rebalance and also prevents placing orders
    // when it's too volatile.
    modifier checkDeviation() {
        pool.checkDeviation(IOptimizerStrategy(strategy).maxTwapDeviation(), IOptimizerStrategy(strategy).twapDuration());
        _;
    }
    
    /// @notice Refunds any ETH balance held by this contract to the `msg.sender`
    /// @dev Useful for bundling with mint or increase liquidity that uses ether, or exact output swaps
    /// that use ether for the input amount
    function refundETH() internal {
        if (address(this).balance > 0) TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }

    /**
     * @notice `setGovernance()` should be called by the existing governance
     * address prior to calling this function.
     */
    function setGovernance(address _governance) external onlyGovernance {
        pendingGovernance = _governance;
    }

    /**
     * @notice Governance address is not updated until the new governance
     * address has called `acceptGovernance()` to accept this responsibility.
     */
    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "PG");
        emit TransferGovernance(governance, pendingGovernance);
        pendingGovernance = address(0);
        governance = msg.sender;
    }

    // Sets new strategy contract address for new settings
    function setStrategy(address _strategy) external onlyGovernance {
        require(_strategy != address(0), "NA");
        strategy = _strategy;
    }

    function approveOperator(address _operator) external onlyGovernance {
        _operatorApproved[_operator] = true;
    }
    
    function disableOperator(address _operator) external onlyGovernance {
        _operatorApproved[_operator] = false;
    }
    
    function isOperator(address _operator) external view returns (bool) {
        return _operatorApproved[_operator];
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!_paused, "P");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        require(_paused, "NP");
        _;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function pause() external onlyGovernance whenNotPaused {
        _paused = true;
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function unpause() external onlyGovernance whenPaused {
        _paused = false;
    }
}
