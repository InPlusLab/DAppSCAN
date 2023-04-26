// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../utils/OwnablePausable.sol";
import "../uniswap/IUniswapV2Router02.sol";
import "../uniswap/IUniswapV2Factory.sol";

contract UniswapMarketMaker is OwnablePausable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    /// @notice Incoming token.
    ERC20 public incoming;

    /// @notice Support token.
    ERC20 public support;

    /// @notice Uniswap router contract address.
    IUniswapV2Router02 public uniswapRouter;

    /// @notice An event thats emitted when an token transferred to recipient.
    event TokenTransfer(address token, address recipient, uint256 amount);

    /// @notice An event thats emitted when an uniswap router contract address changed.
    event UniswapRouterChanged(address newUniswapRouter);

    /// @notice An event thats emitted when an incoming token changed.
    event IncomingChanged(address newIncoming);

    /// @notice An event thats emitted when an liquidity added.
    event LiquidityIncreased(uint256 incoming, uint256 support);

    /// @notice An event thats emitted when an liquidity removed.
    event LiquidityReduced(uint256 lp, uint256 incoming, uint256 support);

    /**
     * @param _incoming Address of incoming token.
     * @param _support Address of support token.
     * @param _uniswapRouter Address of Uniswap router contract.
     */
    constructor(
        address _incoming,
        address _support,
        address _uniswapRouter
    ) public {
        incoming = ERC20(_incoming);
        support = ERC20(_support);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
    }

    /**
     * @notice Transfer incoming token to recipient.
     * @param token Address of transferred token.
     * @param recipient Address of recipient.
     * @param amount Amount of transferred token.
     */
    function transfer(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        require(recipient != address(0), "UniswapMarketMaker::transfer: cannot transfer to the zero address");

        ERC20(token).safeTransfer(recipient, amount);
        emit TokenTransfer(token, recipient, amount);
    }

    /**
     * @notice Changed uniswap router contract address.
     * @param _uniswapRouter Address new uniswap router contract.
     */
    function changeUniswapRouter(address _uniswapRouter) external onlyOwner {
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        emit UniswapRouterChanged(_uniswapRouter);
    }

    /**
     * @notice Change incoming token address.
     * @param _incoming New incoming token address.
     * @param _recipient Address of recipient.
     */
    function changeIncoming(address _incoming, address _recipient) external onlyOwner {
        require(address(incoming) != _incoming, "UniswapMarketMaker::changeIncoming: duplicate incoming token address");

        uint256 balance = incoming.balanceOf(address(this));
        if (balance > 0) {
            incoming.safeTransfer(_recipient, balance);
        }
        incoming = ERC20(_incoming);
        emit IncomingChanged(_incoming);
    }

    /**
     * @notice Buy support token and add liquidity.
     * @param amount Amount of incoming token.
     */
    function buyLiquidity(uint256 amount) external whenNotPaused {
        if (amount > 0) {
            incoming.safeTransferFrom(_msgSender(), address(this), amount);
        }

        address[] memory path = new address[](2);
        path[0] = address(incoming);
        path[1] = address(support);

        uint256 amountIn = incoming.balanceOf(address(this)).div(2);
        require(amountIn > 0, "UniswapMarketMaker::buyLiquidity: not enough funds to buy back");
        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(amountIn, path);
        require(amountsOut.length != 0, "UniswapMarketMaker::buyLiquidity: invalid amounts out length");
        uint256 amountOut = amountsOut[amountsOut.length - 1];
        require(amountOut > 0, "UniswapMarketMaker::buyLiquidity: liquidity pool is empty");

        incoming.safeApprove(address(uniswapRouter), amountIn);
        uniswapRouter.swapExactTokensForTokens(amountIn, amountOut, path, address(this), block.timestamp);

        uint256 incomingBalance = incoming.balanceOf(address(this));
        require(incomingBalance > 0, "UniswapMarketMaker::buyLiquidity: incoming token balance is empty");
        uint256 supportBalance = support.balanceOf(address(this));
        require(supportBalance > 0, "UniswapMarketMaker::buyLiquidity: support token balance is empty");

        incoming.safeApprove(address(uniswapRouter), incomingBalance);
        support.safeApprove(address(uniswapRouter), supportBalance);
        (uint256 amountA, uint256 amountB, ) = uniswapRouter.addLiquidity(address(incoming), address(support), incomingBalance, supportBalance, 0, 0, address(this), block.timestamp);
        emit LiquidityIncreased(amountA, amountB);

        incoming.safeApprove(address(uniswapRouter), 0);
        support.safeApprove(address(uniswapRouter), 0);
    }

    /**
     * @notice Add liquidity.
     * @param incomingAmount Amount of incoming token.
     * @param supportAmount Amount of support token.
     */
    function addLiquidity(uint256 incomingAmount, uint256 supportAmount) external whenNotPaused {
        if (incomingAmount > 0) {
            incoming.safeTransferFrom(_msgSender(), address(this), incomingAmount);
        }
        if (supportAmount > 0) {
            support.safeTransferFrom(_msgSender(), address(this), supportAmount);
        }

        uint256 incomingBalance = incoming.balanceOf(address(this));
        require(incomingBalance > 0, "UniswapMarketMaker::addLiquidity: incoming token balance is empty");
        uint256 supportBalance = support.balanceOf(address(this));
        require(supportBalance > 0, "UniswapMarketMaker::addLiquidity: support token balance is empty");

        incoming.safeApprove(address(uniswapRouter), incomingBalance);
        support.safeApprove(address(uniswapRouter), supportBalance);
        (uint256 amountA, uint256 amountB, ) = uniswapRouter.addLiquidity(address(incoming), address(support), incomingBalance, supportBalance, 0, 0, address(this), block.timestamp);
        emit LiquidityIncreased(amountA, amountB);

        incoming.safeApprove(address(uniswapRouter), 0);
        support.safeApprove(address(uniswapRouter), 0);
    }

    /**
     * @notice Return liquidity pair address.
     * @return Liquidity pair address.
     */
    function liquidityPair() public view returns (address) {
        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(uniswapRouter.factory());
        return uniswapFactory.getPair(address(incoming), address(support));
    }

    /**
     * @notice Remove liquidity.
     * @param amount Amount of liquidity pool token.
     */
    function removeLiquidity(uint256 amount) external onlyOwner {
        address pair = liquidityPair();
        require(pair != address(0), "UniswapMarketMaker::removeLiquidity: liquidity pair not found");

        uint256 lpBalance = ERC20(pair).balanceOf(address(this));
        amount = lpBalance < amount ? lpBalance : amount;
        require(amount > 0, "UniswapMarketMaker::removeLiquidity: zero amount");

        ERC20(pair).safeApprove(address(uniswapRouter), amount);
        (uint256 incomingAmount, uint256 supportAmount) = uniswapRouter.removeLiquidity(address(incoming), address(support), amount, 0, 0, address(this), block.timestamp);
        emit LiquidityReduced(amount, incomingAmount, supportAmount);
    }
}
