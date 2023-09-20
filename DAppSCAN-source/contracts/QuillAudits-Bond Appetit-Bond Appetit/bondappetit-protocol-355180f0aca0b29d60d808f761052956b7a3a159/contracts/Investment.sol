// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./utils/OwnablePausable.sol";
import "./uniswap/IUniswapV2Router02.sol";
import "./GovernanceToken.sol";

contract Investment is OwnablePausable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    ///@notice Address of cumulative token
    ERC20 public cumulative;

    ///@notice Address of governance token
    GovernanceToken public governanceToken;

    ///@notice Date of locking governance token
    uint256 public governanceTokenLockDate;

    uint8 internal constant GOVERNANCE_TOKEN_PRICE_DECIMALS = 6;

    ///@notice Price governance token
    uint256 public governanceTokenPrice = 1000000;

    ///@dev Address of UniswapV2Router
    IUniswapV2Router02 internal uniswapRouter;

    ///@notice Investment tokens list
    mapping(address => bool) public investmentTokens;

    /// @notice An event thats emitted when an uniswap router contract address changed.
    event UniswapRouterChanged(address newUniswapRouter);

    /// @notice An event thats emitted when an invest token allowed.
    event InvestTokenAllowed(address token);

    /// @notice An event thats emitted when an invest token denied.
    event InvestTokenDenied(address token);

    /// @notice An event thats emitted when an governance token price changed.
    event GovernanceTokenPriceChanged(uint256 newPrice);

    /// @notice An event thats emitted when an invested token.
    event Invested(address investor, address token, uint256 amount, uint256 reward);

    /// @notice An event thats emitted when an withdrawal token.
    event Withdrawal(address recipient, address token, uint256 amount);

    /**
     * @param _cumulative Address of cumulative token
     * @param _governanceToken Address of governance token
     * @param _uniswapRouter Address of UniswapV2Router
     */
    constructor(
        address _cumulative,
        address _governanceToken,
        uint256 _governanceTokenLockDate,
        address _uniswapRouter
    ) public {
        cumulative = ERC20(_cumulative);
        governanceToken = GovernanceToken(_governanceToken);
        governanceTokenLockDate = _governanceTokenLockDate;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
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
     * @notice Add token to investable tokens white list
     * @param token Allowable token
     */
    function allowToken(address token) external onlyOwner {
        investmentTokens[token] = true;
        emit InvestTokenAllowed(token);
    }

    /**
     * @notice Remove token from investable tokens white list
     * @param token Denied token
     */
    function denyToken(address token) external onlyOwner {
        investmentTokens[token] = false;
        emit InvestTokenDenied(token);
    }

    /**
     * @notice Update governance token price
     * @param newPrice New price of governance token of USD (6 decimal)
     */
    function changeGovernanceTokenPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Investment::changeGovernanceTokenPrice: invalid new governance token price");

        governanceTokenPrice = newPrice;
        emit GovernanceTokenPriceChanged(newPrice);
    }

    /**
     * @param token Invested token
     * @return Pools for each consecutive pair of addresses must exist and have liquidity
     */
    function _path(address token) internal view returns (address[] memory) {
        address weth = uniswapRouter.WETH();
        if (weth == token) {
            address[] memory path = new address[](2);
            path[0] = token;
            path[1] = address(cumulative);
            return path;
        }

        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = weth;
        path[2] = address(cumulative);
        return path;
    }

    /**
     * @param token Invested token
     * @param amount Invested amount
     * @return Amount cumulative token after swap
     */
    function _amountOut(address token, uint256 amount) internal view returns (uint256) {
        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(amount, _path(token));
        require(amountsOut.length != 0, "Investment::_amountOut: invalid amounts out length");

        return amountsOut[amountsOut.length - 1];
    }

    /**
     * @param amount Cumulative amount invested
     * @return Amount governance token after swap
     */
    //  SWC-101-Integer Overflow and Underflow: L148
    function _governanceTokenPrice(uint256 amount) internal view returns (uint256) {
        uint256 decimals = cumulative.decimals();

        return amount.mul(10**(18 - decimals + GOVERNANCE_TOKEN_PRICE_DECIMALS)).div(governanceTokenPrice);
    }

    /**
     * @param token Invested token
     * @param amount Invested amount
     * @return Amount governance token after swap
     */
    function price(address token, uint256 amount) external view returns (uint256) {
        require(investmentTokens[token], "Investment::price: invalid investable token");

        uint256 amountOut = amount;
        if (token != address(cumulative)) {
            amountOut = _amountOut(token, amount);
        }

        return _governanceTokenPrice(amountOut);
    }

    /**
     * @notice Invest tokens to protocol
     * @param token Invested token
     * @param amount Invested amount
     */
    function invest(address token, uint256 amount) external whenNotPaused returns (bool) {
        require(investmentTokens[token], "Investment::invest: invalid investable token");
        uint256 reward = _governanceTokenPrice(amount);

        ERC20(token).safeTransferFrom(_msgSender(), address(this), amount);

        if (token != address(cumulative)) {
            uint256 amountOut = _amountOut(token, amount);
            require(amountOut != 0, "Investment::invest: liquidity pool is empty");
            reward = _governanceTokenPrice(amountOut);

            ERC20(token).safeApprove(address(uniswapRouter), amount);
            uniswapRouter.swapExactTokensForTokens(amount, amountOut, _path(token), address(this), block.timestamp);
        }

        governanceToken.transferLock(_msgSender(), reward, governanceTokenLockDate);

        emit Invested(_msgSender(), token, amount, reward);
        return true;
    }

    /**
     * @notice Invest ETH to protocol
     */
    function investETH() external payable whenNotPaused returns (bool) {
        address token = uniswapRouter.WETH();
        require(investmentTokens[token], "Investment::investETH: invalid investable token");
        uint256 reward = _governanceTokenPrice(msg.value);

        if (token != address(cumulative)) {
            uint256 amountOut = _amountOut(token, msg.value);
            require(amountOut != 0, "Investment::invest: liquidity pool is empty");
            reward = _governanceTokenPrice(amountOut);

            uniswapRouter.swapExactETHForTokens{value: msg.value}(amountOut, _path(token), address(this), block.timestamp);
        }

        governanceToken.transferLock(_msgSender(), reward, governanceTokenLockDate);

        emit Invested(_msgSender(), token, msg.value, reward);
        return true;
    }

    /**
     * @notice Withdraw invested token to address
     * @param recipient Recipient of tokens
     */
    function withdraw(address recipient) external onlyOwner {
        require(recipient != address(0), "Investment::withdraw: cannot transfer to the zero address");

        uint256 balance = cumulative.balanceOf(address(this));
        cumulative.safeTransfer(recipient, balance);

        emit Withdrawal(recipient, address(cumulative), balance);
    }
}
