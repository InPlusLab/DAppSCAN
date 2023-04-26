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

    /// @notice Address of cumulative token.
    ERC20 public cumulative;

    /// @notice Address of stable token contract.
    ERC20 public stableToken;

    /// @notice Address of governance token contract.
    ERC20 public governanceToken;

    /// @notice Price of governance token
    uint256 public governanceTokenPrice = 1000000;

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

    /// @notice An event thats emitted when an governance token price changed.
    event GovernanceTokenPriceChanged(uint256 newPrice);

    /// @notice An event thats emitted when an account buyed token.
    event Buy(address customer, address product, address token, uint256 amount, uint256 buy);

    /// @notice An event thats emitted when an cumulative token withdrawal.
    event Withdrawal(address recipient, address token, uint256 amount);

    /**
     * @param _cumulative Address of cumulative token.
     * @param _stableToken Address of stable token.
     * @param _governanceToken Address of governance token.
     * @param _uniswapRouter Address of Uniswap router contract.
     * @param _priceOracle Address of Price oracle contract.
     */
    constructor(
        address _cumulative,
        address _stableToken,
        address _governanceToken,
        address _uniswapRouter,
        address _priceOracle
    ) public {
        cumulative = ERC20(_cumulative);
        stableToken = ERC20(_stableToken);
        governanceToken = ERC20(_governanceToken);
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
     * @notice Update price of governance token.
     * @param newPrice New price of governance token of USD (6 decimal).
     */
    function changeGovernanceTokenPrice(uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Market::changeGovernanceTokenPrice: invalid new price of governance token");

        governanceTokenPrice = newPrice;
        emit GovernanceTokenPriceChanged(newPrice);
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
     * @notice Transfer stable token to recipient.
     * @param recipient Address of recipient.
     * @param amount Amount of transfered token.
     */
    function transferStableToken(address recipient, uint256 amount) external onlyOwner {
        transfer(stableToken, recipient, amount);
    }

    /**
     * @notice Transfer governance token to recipient.
     * @param recipient Address of recipient.
     * @param amount Amount of transfered token.
     */
    function transferGovernanceToken(address recipient, uint256 amount) external onlyOwner {
        transfer(governanceToken, recipient, amount);
    }

    /**
     * @dev Convert token amount to governance token amount.
     * @param amount Target token amount.
     * @return Governance token amount.
     */
    function _governanceTokenPrice(uint256 amount) internal view returns (uint256) {
        return amount.mul(10**PRICE_DECIMALS).div(governanceTokenPrice);
    }

    /**
     * @dev Get product token price from payment token amount.
     * @param product Product token.
     * @param token Payment token.
     * @param amount Payment token amount.
     * @return Price of product token.
     */
    function price(
        ERC20 product,
        ERC20 token,
        uint256 amount
    ) internal view returns (uint256) {
        require(isAllowedToken(address(token)), "Market::price: invalid token");

        uint256 tokenDecimals = token.decimals();
        uint256 productDecimals = product.decimals();
        uint256 tokenPrice = priceOracle.price(allowedTokens[address(token)]);
        uint256 cumulativePrice = priceOracle.price(cumulative.symbol());

        uint256 result = amount.mul(10**productDecimals.sub(tokenDecimals));
        if (address(product) != address(token)) {
            result = tokenPrice.mul(10**PRICE_DECIMALS).div(cumulativePrice).mul(amount).div(10**PRICE_DECIMALS).mul(10**productDecimals.sub(tokenDecimals));
        }
        if (address(product) == address(governanceToken)) {
            return _governanceTokenPrice(result);
        }

        return result;
    }

    /**
     * @dev Get stable token price from payment token amount.
     * @param token Payment token.
     * @param amount Payment token amount.
     * @return Price of product token.
     */
    function priceStableToken(address token, uint256 amount) external view returns (uint256) {
        return price(stableToken, ERC20(token), amount);
    }

    /**
     * @dev Get governance token price from payment token amount.
     * @param token Payment token.
     * @param amount Payment token amount.
     * @return Price of product token.
     */
    function priceGovernanceToken(address token, uint256 amount) external view returns (uint256) {
        return price(governanceToken, ERC20(token), amount);
    }

    /**
     * @param token Buy token.
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
     * @param token Buy token.
     * @param amount Buy amount.
     * @return Amount cumulative token after swap.
     */
    function _amountOut(address token, uint256 amount) internal view returns (uint256) {
        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(amount, _path(token));
        require(amountsOut.length != 0, "Market::_amountOut: invalid amounts out length");

        return amountsOut[amountsOut.length - 1];
    }

    /**
     * @dev Buy product token with ERC20 payment token amount.
     * @param product Purchased token.
     * @param token Payment token.
     * @param amount Amount of payment token.
     * @return True if success.
     */
    function buy(
        ERC20 product,
        ERC20 token,
        uint256 amount
    ) internal whenNotPaused returns (bool) {
        require(isAllowedToken(address(token)), "Market::buy: invalid token");

        uint256 reward = price(product, token, amount);
        token.safeTransferFrom(msg.sender, address(this), amount);

        if (address(token) != address(cumulative)) {
            uint256 amountOut = _amountOut(address(token), amount);
            require(amountOut != 0, "Market::buy: liquidity pool is empty");

            token.safeApprove(address(uniswapRouter), amount);
            uniswapRouter.swapExactTokensForTokens(amount, amountOut, _path(address(token)), address(this), block.timestamp);
        }

        product.safeTransfer(msg.sender, reward);
        emit Buy(msg.sender, address(product), address(token), amount, reward);

        return true;
    }

    /**
     * @notice Buy stable token with ERC20 payment token amount.
     * @param token Payment token.
     * @param amount Amount of payment token.
     * @return True if success.
     */
    function buyStableToken(address token, uint256 amount) external returns (bool) {
        return buy(stableToken, ERC20(token), amount);
    }

    /**
     * @notice Buy governance token with ERC20 payment token amount.
     * @param token Payment token.
     * @param amount Amount of payment token.
     * @return True if success.
     */
    function buyGovernanceToken(address token, uint256 amount) external returns (bool) {
        require(governanceToken.balanceOf(msg.sender) > 0, "Market::buyGovernanceToken: only tokenholder can buy new governance token");

        return buy(governanceToken, ERC20(token), amount);
    }

    /**
     * @dev Buy product token with ETH amount.
     * @param product Purchased token.
     * @return True if success.
     */
    function buyFromETH(ERC20 product) internal whenNotPaused returns (bool) {
        ERC20 token = ERC20(uniswapRouter.WETH());
        uint256 amount = msg.value;
        require(isAllowedToken(address(token)), "Market::buyFromETH: invalid token");

        uint256 reward = price(product, token, amount);

        if (address(token) != address(cumulative)) {
            uint256 amountOut = _amountOut(address(token), amount);
            require(amountOut != 0, "Market::buyFromETH: liquidity pool is empty");

            uniswapRouter.swapExactETHForTokens{value: amount}(amountOut, _path(address(token)), address(this), block.timestamp);
        }

        product.safeTransfer(msg.sender, reward);
        emit Buy(msg.sender, address(product), address(token), amount, reward);

        return true;
    }

    /**
     * @notice Buy stable token with ETH amount.
     * @return True if success.
     */
    function buyStableTokenFromETH() external payable returns (bool) {
        return buyFromETH(stableToken);
    }

    /**
     * @notice Buy governance token with ETH amount.
     * @return True if success.
     */
    function buyGovernanceTokenFromETH() external payable returns (bool) {
        require(governanceToken.balanceOf(msg.sender) > 0, "Market::buyGovernanceTokenFromETH: only tokenholder can buy new governance token");

        return buyFromETH(governanceToken);
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
