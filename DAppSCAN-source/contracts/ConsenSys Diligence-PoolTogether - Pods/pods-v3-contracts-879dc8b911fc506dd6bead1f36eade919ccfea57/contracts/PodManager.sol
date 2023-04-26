// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

// Libraries
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

// Interfaces
import "./IPod.sol";
import "./IPodManager.sol";
import "./interfaces/uniswap/IUniswapV2Router02.sol";

/**
 * @title PodManager Prototype (Ownable, IPodManager) - Liquidates a Pod non-core Assets
 * @notice Manages the liqudiation of a Pods "bonus" winnings i.e. tokens earned from LOOT boxes and other unexpected assets transfered to the Pod
 * @dev Liquidates non-core tokens (deposit token, PrizePool tickets and the POOL goverance) token for fair distribution Pod winners.
 * @author Kames Geraghty
 */
contract PodManager is Ownable, IPodManager {
    /***********************************|
    |   Libraries                       |
    |__________________________________*/
    using SafeMath for uint256;

    /***********************************|
    |   Constants                       |
    |__________________________________*/
    // Uniswap Router
    IUniswapV2Router02 public uniswapRouter =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    /***********************************|
    |   Events                          |
    |__________________________________*/
    /**
     * @dev Log Emitted when PodManager liquidates a Pod ERC20 token
     */
    event LogLiquidatedERC20(
        address token,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * @dev Log Emitted when PodManager withdraws a Pod ERC20 token
     */
    event LogLiquidatedERC721(address token, uint256 tokenId);

    /***********************************|
    |   Public/External                 |
    |__________________________________*/
    /**
     * @notice Liqudiates an ERC20 from a Pod by withdrawin the non-core token, executing a swap and returning the token.
     * @dev Liqudiates an ERC20 from a Pod by withdrawin the non-core token, executing a swap and returning the token.
     * @param _pod Pod reference
     * @param target ERC20 token reference.
     * @param amountIn Exact token amount transfered
     * @param amountOutMin Minimum token receieved
     * @param path Uniswap token path
     */
    function liquidate(
        address _pod,
        IERC20Upgradeable target,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) external override returns (bool) {
        IPod pod = IPod(_pod);

        // Withdraw target token from Pod
        pod.withdrawERC20(target, amountIn);

        // Approve Uniswap Router Swap
        target.approve(address(uniswapRouter), amountIn);

        // Swap Tokens and Send Winnings to PrizePool Pod
        uniswapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(pod),
            block.timestamp
        );

        // Emit LogLiquidatedERC20
        emit LogLiquidatedERC20(address(target), amountIn, amountOutMin);

        return true;
    }

    /**
     * @notice liquidate
     * @return uint256 Amount liquidated
     */
    function withdrawCollectible(
        address _pod,
        IERC721 target,
        uint256 tokenId
    ) external override returns (bool) {
        IPod pod = IPod(_pod);

        // Withdraw target ERC721 from Pod
        pod.withdrawERC721(target, tokenId);

        // Transfer Collectible to Owner
        target.transferFrom(address(this), owner(), tokenId);

        // Emit LogLiquidatedERC721
        emit LogLiquidatedERC721(address(target), tokenId);

        return true;
    }
}
