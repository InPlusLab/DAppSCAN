// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '../libraries/SwapLibrary.sol';
import '../libraries/TransferHelper.sol';
import '../interfaces/ISwapRouter02.sol';
import '../interfaces/ISwapFactory.sol';
import '../interfaces/IWOKT.sol';
import "../libraries/TransferHelper.sol";
import "../interfaces/ISwapAdapter.sol";

interface ITradingPool {
    function swap(
        address account,
        address input,
        address output,
        uint256 amount
    ) external returns (bool);
}

contract SwapRouter is ISwapRouter02, Ownable {
    using SafeMath for uint256;

    struct PoolInfo {
        uint256 direction;
        uint256 poolEdition;
        uint256 weight;
        address pool;
        address adapter;
        bytes moreInfo;
    }

    event ExSwap(
        address fromToken,
        address toToken,
        address sender,
        uint256 fromAmount,
        uint256 returnAmount
    );

    address public immutable override factory;
    address public immutable override WOKT;
    address public override tradingPool;
    mapping (address => bool) public isWhiteListed;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'SwapRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WOKT) public {
        factory = _factory;
        WOKT = _WOKT;
    }

    receive() external payable {
        assert(msg.sender == WOKT); // only accept OKT via fallback from the WOKT contract
    }

    function addWhiteList (address contractAddr) public onlyOwner {
        isWhiteListed[contractAddr] = true;
    }

    function removeWhiteList (address contractAddr) public onlyOwner {
        isWhiteListed[contractAddr] = false;
    }

    function setTradingPool(address _tradingPool) public onlyOwner {
        tradingPool = _tradingPool;
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (ISwapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            ISwapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = SwapLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = SwapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'SwapRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = SwapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'SwapRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    
    function pairFor(address tokenA, address tokenB) public view returns(address) {
        return SwapLibrary.pairFor(factory, tokenA, tokenB);
    }

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
        virtual
        override
        ensure(deadline)
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = SwapLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = ISwapPair(pair).mint(to);
    }

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
        virtual
        override
        ensure(deadline)
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        )
    {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WOKT,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = SwapLibrary.pairFor(factory, token, WOKT);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWOKT(WOKT).deposit{value: amountETH}();
        assert(IWOKT(WOKT).transfer(pair, amountETH));
        liquidity = ISwapPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = SwapLibrary.pairFor(factory, tokenA, tokenB);
        ISwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = ISwapPair(pair).burn(to);
        (address token0, ) = SwapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'SwapRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'SwapRouter: INSUFFICIENT_B_AMOUNT');
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WOKT,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWOKT(WOKT).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

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
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        address pair = SwapLibrary.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        ISwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

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
    ) external virtual override returns (uint256 amountToken, uint256 amountETH) {
        address pair = SwapLibrary.pairFor(factory, token, WOKT);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        ISwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountETH) {
        (, amountETH) = removeLiquidity(token, WOKT, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWOKT(WOKT).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
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
    ) external virtual override returns (uint256 amountETH) {
        address pair = SwapLibrary.pairFor(factory, token, WOKT);
        uint256 value = approveMax ? uint256(-1) : liquidity;
        ISwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token,
            liquidity,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = SwapLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            if (tradingPool != address(0)) {
                ITradingPool(tradingPool).swap(msg.sender, input, output, amountOut);
            }
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? SwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            ISwapPair(SwapLibrary.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = SwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            SwapLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = SwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'SwapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            SwapLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WOKT, 'SwapRouter: INVALID_PATH');
        amounts = SwapLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWOKT(WOKT).deposit{value: amounts[0]}();
        assert(IWOKT(WOKT).transfer(SwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WOKT, 'SwapRouter: INVALID_PATH');
        amounts = SwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'SwapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            SwapLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWOKT(WOKT).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WOKT, 'SwapRouter: INVALID_PATH');
        amounts = SwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            SwapLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWOKT(WOKT).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WOKT, 'SwapRouter: INVALID_PATH');
        amounts = SwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'SwapRouter: EXCESSIVE_INPUT_AMOUNT');
        IWOKT(WOKT).deposit{value: amounts[0]}();
        assert(IWOKT(WOKT).transfer(SwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = SwapLibrary.sortTokens(input, output);
            ISwapPair pair = ISwapPair(SwapLibrary.pairFor(factory, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) =
                    input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
                amountOutput = SwapLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            if (tradingPool != address(0)) {
                ITradingPool(tradingPool).swap(msg.sender, input, output, amountOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? SwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(path[0], msg.sender, SwapLibrary.pairFor(factory, path[0], path[1]), amountIn);
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) {
        require(path[0] == WOKT, 'SwapRouter: INVALID_PATH');
        uint256 amountIn = msg.value;
        IWOKT(WOKT).deposit{value: amountIn}();
        assert(IWOKT(WOKT).transfer(SwapLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        require(path[path.length - 1] == WOKT, 'SwapRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(path[0], msg.sender, SwapLibrary.pairFor(factory, path[0], path[1]), amountIn);
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(WOKT).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'SwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWOKT(WOKT).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    /**** mix swap  ****/

    function externalSwap(
        address fromToken,
        address toToken,
        address approveTarget,
        address swapTarget,
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        bytes memory callDataConcat,
        uint256 deadLine
    )
    external
    override
    payable
    ensure(deadLine)
    returns (uint256 returnAmount)
    {
        require(minReturnAmount > 0, "SwapRouter: RETURN_AMOUNT_ZERO");

        uint256 toTokenOriginBalance = TransferHelper.universalBalanceOf(toToken, msg.sender);
        if (!TransferHelper.isETH(fromToken)) {
            TransferHelper.safeTransferFrom(fromToken, msg.sender, address(this), fromTokenAmount);

            TransferHelper.universalApproveMax(fromToken, approveTarget, fromTokenAmount);
        }

        require(isWhiteListed[swapTarget], "SwapRouter: Not Whitelist Contract");
        (bool success, ) = swapTarget.call{value: TransferHelper.isETH(fromToken) ? msg.value : 0}(callDataConcat);

        require(success, "SwapRouter: External Swap execution Failed");

        TransferHelper.universalTransfer(
            toToken, msg.sender, TransferHelper.universalBalanceOf(toToken, address(this))
        );

        returnAmount = TransferHelper.universalBalanceOf(toToken, msg.sender).sub(toTokenOriginBalance);
        require(returnAmount >= minReturnAmount, "SwapRouter: Return amount is not enough");

        emit ExSwap(fromToken, toToken, msg.sender, fromTokenAmount, returnAmount);
    }

    function mixSwap(
        address fromToken,
        address toToken,
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        address[] memory mixAdapters,
        address[] memory mixPairs,
        address[] memory assetTo,
        uint256 directions,
        uint256 deadLine
    ) external override payable ensure(deadLine) returns (uint256 returnAmount) {
        require(mixPairs.length > 0, "SwapRouter: PAIRS_EMPTY");
        require(mixPairs.length == mixAdapters.length, "SwapRouter: PAIR_ADAPTER_NOT_MATCH");
        require(mixPairs.length == assetTo.length - 1, "SwapRouter: PAIR_ASSETTO_NOT_MATCH");
        require(minReturnAmount > 0, "SwapRouter: RETURN_AMOUNT_ZERO");

        address _fromToken = fromToken;
        address _toToken = toToken;
        uint256 _fromTokenAmount = fromTokenAmount;

        uint256 toTokenOriginBalance = TransferHelper.universalBalanceOf(_toToken, msg.sender);

        _deposit(msg.sender, assetTo[0], _fromToken, _fromTokenAmount, TransferHelper.isETH(_fromToken));

        for (uint256 i = 0; i < mixPairs.length; i++) {
            if (directions & 1 == 0) {
                ISwapAdapter(mixAdapters[i]).sellBase(assetTo[i + 1], mixPairs[i], "");
            } else {
                ISwapAdapter(mixAdapters[i]).sellQuote(assetTo[i + 1], mixPairs[i], "");
            }
            directions = directions >> 1;
        }

        if(TransferHelper.isETH(_toToken)) {
            returnAmount = IWOKT(WOKT).balanceOf(address(this));
            IWOKT(WOKT).withdraw(returnAmount);
            msg.sender.transfer(returnAmount);
        } else {
            returnAmount = TransferHelper.tokenBalanceOf(_toToken, msg.sender).sub(toTokenOriginBalance);
        }

        require(returnAmount >= minReturnAmount, "SwapRouter: Return amount is not enough");

        emit ExSwap(fromToken, toToken, msg.sender, _fromTokenAmount, returnAmount);
    }

    function polySwap(
        address fromToken,
        address toToken,
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        uint[] memory weights,
        address[] memory adapters,
        address[] memory pools,
        uint256 directions,
        uint256 deadLine
    ) external payable override ensure(deadLine) returns (uint256 returnAmount) {
        require(pools.length == adapters.length, 'SwapRouter: POOL_ADAPTER_NOT_MATCH');
        require(minReturnAmount > 0, "SwapRouter: RETURN_AMOUNT_ZERO");

        uint256 _fromTokenAmount = fromTokenAmount;
        uint256 toTokenOriginBalance = TransferHelper.universalBalanceOf(toToken, msg.sender);
        address _fromToken = fromToken;

        _deposit(msg.sender, address(this), _fromToken, _fromTokenAmount, TransferHelper.isETH(_fromToken));

        address midTo = msg.sender;
        if (TransferHelper.isETH(_fromToken)) {
            midTo = address(this);
        }

        address _toToken = toToken;
        address[] memory _adapters = adapters;
        uint[] memory _weights = weights;
        address[] memory _pools = pools;
        for(uint256 i = 0; i < _adapters.length; i++) {
            uint256 curAmount = _fromTokenAmount.mul(uint256(_weights[i])).div(100);
            IERC20(_fromToken).transfer(_pools[i], curAmount);

            if (directions & 1 == 0) {
                ISwapAdapter(_adapters[i]).sellBase(midTo, _pools[i], "");
            } else {
                ISwapAdapter(_adapters[i]).sellQuote(midTo, _pools[i], "");
            }
            directions = directions >> 1;
        }

        if(TransferHelper.isETH(_toToken)) {
            returnAmount = IWOKT(WOKT).balanceOf(address(this));
            IWOKT(WOKT).withdraw(returnAmount);
            msg.sender.transfer(returnAmount);
        }else {
            returnAmount = TransferHelper.tokenBalanceOf(_toToken, msg.sender).sub(toTokenOriginBalance);
        }

        require(returnAmount >= minReturnAmount, "SwapRouter: Return amount is not enough");

        emit ExSwap(_fromToken, _toToken, msg.sender, _fromTokenAmount, returnAmount);
    }

    function _deposit(
        address from,
        address to,
        address token,
        uint256 amount,
        bool isETH
    ) internal {
        if (isETH) {
            if (amount > 0) {
                IWOKT(WOKT).deposit{value: amount}();
                if (to != address(this)) TransferHelper.safeTransfer(WOKT, to, amount);
            }
        } else {
            TransferHelper.safeTransferFrom(token, from, to, amount);
        }
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure virtual override returns (uint256 amountB) {
        return SwapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountOut) {
        return SwapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountIn) {
        return SwapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return SwapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return SwapLibrary.getAmountsIn(factory, amountOut, path);
    }
}
