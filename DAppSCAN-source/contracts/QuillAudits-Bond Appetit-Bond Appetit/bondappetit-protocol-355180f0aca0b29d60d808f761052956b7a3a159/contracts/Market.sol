// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./utils/OwnablePausable.sol";
import "./uniswap/IUniswapV2Router02.sol";
import "./uniswap/IUniswapAnchoredView.sol";

contract Market is OwnablePausable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    uint256 public constant PRICE_DECIMALS = 6;

    uint256 public constant REWARD_DECIMALS = 12;

    /// @notice Address of cumulative token.
    ERC20 public cumulative;

    /// @notice Address of product token contract.
    ERC20 public productToken;

    /// @notice Address of reward token contract.
    ERC20 public rewardToken;

    /// @dev Address of UniswapV2Router.
    IUniswapV2Router02 public uniswapRouter;

    /// @dev Address of IUniswapAnchoredView.
    IUniswapAnchoredView public priceOracle;

    /// @dev Allowed tokens symbols list.
    mapping(address => string) internal allowedTokens;

    /// @notice An event thats emitted when an price oracle contract address changed.
    event PriceOracleChanged(address newPriceOracle);

    /// @notice An event thats emitted when an uniswap router contract address changed.
    event UniswapRouterChanged(address newUniswapRouter);

    /// @notice An event thats emitted when an cumulative token changed.
    event CumulativeChanged(address newToken);

    /// @notice An event thats emitted when an token allowed.
    event TokenAllowed(address token, string symbol);

    /// @notice An event thats emitted when an token denied.
    event TokenDenied(address token);

    /// @notice An event thats emitted when an account buyed token.
    event Buy(address customer, address token, uint256 amount, uint256 buy, uint256 reward);

    /// @notice An event thats emitted when an cumulative token withdrawal.
    event Withdrawal(address recipient, address token, uint256 amount);

    /**
     * @param _cumulative Address of cumulative token.
     * @param _productToken Address of product token.
     * @param _rewardToken Address of reward token.
     * @param _uniswapRouter Address of Uniswap router contract.
     * @param _priceOracle Address of Price oracle contract.
     */
    constructor(
        address _cumulative,
        address _productToken,
        address _rewardToken,
        address _uniswapRouter,
        address _priceOracle
    ) public {
        cumulative = ERC20(_cumulative);
        productToken = ERC20(_productToken);
        rewardToken = ERC20(_rewardToken);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        priceOracle = IUniswapAnchoredView(_priceOracle);
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
     * @notice Changed price oracle contract address.
     * @param _priceOracle Address new price oracle contract.
     */
    function changePriceOracle(address _priceOracle) external onlyOwner {
        priceOracle = IUniswapAnchoredView(_priceOracle);
        emit PriceOracleChanged(_priceOracle);
    }

    /**
     * @notice Changed cumulative token address.
     * @param newToken Address new cumulative token.
     * @param recipient Address of recipient for withdraw current cumulative balance.
     */
    function changeCumulativeToken(address newToken, address recipient) external onlyOwner {
        withdraw(recipient);
        cumulative = ERC20(newToken);
        emit CumulativeChanged(newToken);
    }

    /**
     * @notice Add token to tokens white list.
     * @param token Allowable token.
     * @param symbol Symbol target token of price oracle contract.
     */
    function allowToken(address token, string calldata symbol) external onlyOwner {
        allowedTokens[token] = symbol;
        emit TokenAllowed(token, symbol);
    }

    /**
     * @notice Remove token from tokens white list.
     * @param token Denied token.
     */
    function denyToken(address token) external onlyOwner {
        allowedTokens[token] = "";
        emit TokenDenied(token);
    }

    /**
     * @param token Target token.
     * @return Is target token allowed.
     */
    function isAllowedToken(address token) public view returns (bool) {
        return bytes(allowedTokens[token]).length != 0;
    }

    /**
     * @dev Transfer token to recipient.
     * @param from Address of transfered token contract.
     * @param recipient Address of recipient.
     * @param amount Amount of transfered token.
     */
    function transfer(
        ERC20 from,
        address recipient,
        uint256 amount
    ) internal {
        require(recipient != address(0), "Market::transfer: cannot transfer to the zero address");

        uint256 currentBalance = from.balanceOf(address(this));
        require(amount <= currentBalance, "Market::transfer: not enough tokens");

        from.safeTransfer(recipient, amount);
    }

    /**
     * @notice Transfer product token to recipient.
     * @param recipient Address of recipient.
     * @param amount Amount of transfered token.
     */
    function transferProductToken(address recipient, uint256 amount) external onlyOwner {
        transfer(productToken, recipient, amount);
    }

    /**
     * @notice Transfer reward token to recipient.
     * @param recipient Address of recipient.
     * @param amount Amount of transfered token.
     */
    function transferRewardToken(address recipient, uint256 amount) external onlyOwner {
        transfer(rewardToken, recipient, amount);
    }

    /**
     * @notice Get token price.
     * @param currency Currency token.
     * @param payment Amount of payment.
     * @return product Amount of product token.
     * @return reward Amount of reward token.
     */
    //  SWC-135-Code With No Effects: L189
    function price(address currency, uint256 payment) public view returns (uint256 product, uint256 reward) {
        require(isAllowedToken(currency), "Market::price: currency not allowed");

        uint256 tokenDecimals = ERC20(currency).decimals();
        uint256 productDecimals = productToken.decimals();
        uint256 tokenPrice = priceOracle.price(allowedTokens[currency]);
        uint256 cumulativePrice = priceOracle.price(cumulative.symbol());

        product = payment.mul(10**productDecimals.sub(tokenDecimals));
        if (address(productToken) != currency) {
            product = tokenPrice.mul(10**PRICE_DECIMALS).div(cumulativePrice).mul(payment).div(10**PRICE_DECIMALS).mul(10**productDecimals.sub(tokenDecimals));
        }

        uint256 productTokenBalance = productToken.balanceOf(address(this));
        if (productTokenBalance > 0) {
            uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
            reward = product.mul(10**REWARD_DECIMALS).div(productTokenBalance).mul(rewardTokenBalance).div(10**REWARD_DECIMALS);
        }
    }

    /**
     * @param currency Currency token.
     * @return Pools for each consecutive pair of addresses must exist and have liquidity
     */
    function _path(address currency) internal view returns (address[] memory) {
        address weth = uniswapRouter.WETH();
        if (weth == currency) {
            address[] memory path = new address[](2);
            path[0] = currency;
            path[1] = address(cumulative);
            return path;
        }

        address[] memory path = new address[](3);
        path[0] = currency;
        path[1] = weth;
        path[2] = address(cumulative);
        return path;
    }

    /**
     * @param currency Currency token.
     * @param payment Amount of payment.
     * @return Amount cumulative token after swap.
     */
    function _amountOut(address currency, uint256 payment) internal view returns (uint256) {
        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(payment, _path(currency));
        require(amountsOut.length != 0, "Market::_amountOut: invalid amounts out length");

        return amountsOut[amountsOut.length - 1];
    }

    /**
     * @notice Buy token with ERC20.
     * @param currency Currency token.
     * @param payment Amount of payment.
     * @return True if success.
     */
    function buy(address currency, uint256 payment) external whenNotPaused returns (bool) {
        (uint256 product, uint256 reward) = price(currency, payment);
        uint256 productTokenBalance = productToken.balanceOf(address(this));
        require(productTokenBalance > 0 && product <= productTokenBalance, "Market::buy: exceeds balance");

        ERC20(currency).safeTransferFrom(_msgSender(), address(this), payment);

        if (currency != address(cumulative)) {
            uint256 amountOut = _amountOut(currency, payment);
            require(amountOut != 0, "Market::buy: liquidity pool is empty");

            ERC20(currency).safeApprove(address(uniswapRouter), payment);
            uniswapRouter.swapExactTokensForTokens(payment, amountOut, _path(currency), address(this), block.timestamp);
        }

        productToken.safeTransfer(_msgSender(), product);
        if (reward > 0) {
            rewardToken.safeTransfer(_msgSender(), reward);
        }
        emit Buy(_msgSender(), currency, payment, product, reward);

        return true;
    }

    /**
     * @notice Buy token with ETH.
     * @return True if success.
     */
    function buyFromETH() external payable whenNotPaused returns (bool) {
        address currency = uniswapRouter.WETH();
        uint256 payment = msg.value;

        (uint256 product, uint256 reward) = price(currency, payment);
        uint256 productTokenBalance = productToken.balanceOf(address(this));
        require(product <= productTokenBalance, "Market::buyFromETH: balance is empty");

        if (currency != address(cumulative)) {
            uint256 amountOut = _amountOut(currency, payment);
            require(amountOut != 0, "Market::buyFromETH: liquidity pool is empty");

            uniswapRouter.swapExactETHForTokens{value: payment}(amountOut, _path(currency), address(this), block.timestamp);
        }

        productToken.safeTransfer(_msgSender(), product);
        if (reward > 0) {
            rewardToken.safeTransfer(_msgSender(), reward);
        }
        emit Buy(_msgSender(), currency, payment, product, reward);

        return true;
    }

    /**
     * @notice Withdraw cumulative token to address.
     * @param recipient Recipient of token.
     */
    function withdraw(address recipient) public onlyOwner {
        require(recipient != address(0), "Market::withdraw: cannot transfer to the zero address");

        uint256 balance = cumulative.balanceOf(address(this));
        cumulative.safeTransfer(recipient, balance);

        emit Withdrawal(recipient, address(cumulative), balance);
    }
}
