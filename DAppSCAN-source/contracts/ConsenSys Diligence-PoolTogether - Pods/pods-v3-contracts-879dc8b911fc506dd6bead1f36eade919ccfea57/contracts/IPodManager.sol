// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

// Interface
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IPodManager {
    /**
     * @notice liquidate
     * @return uint256 Amount liquidated
     */
    function liquidate(
        address _pod,
        IERC20Upgradeable target,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) external returns (bool);

    /**
     * @notice withdrawCollectible
     * @return uint256 Amount liquidated
     */
    function withdrawCollectible(
        address _pod,
        IERC721 target,
        uint256 tokenId
    ) external returns (bool);
}
