// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '../helpers/UniswapNFTHelper.sol';
import '../../interfaces/IPositionManager.sol';
import '../../interfaces/IPositionManagerFactory.sol';
import '../../interfaces/IUniswapAddressHolder.sol';
import '../../interfaces/actions/ICollectFees.sol';
import '../../interfaces/actions/IClosePosition.sol';
import '../../interfaces/actions/IDecreaseLiquidity.sol';
import '../../interfaces/actions/IZapOut.sol';

///@notice WithdrawRecipes allows user to withdraw positions from PositionManager
contract WithdrawRecipes {
    IPositionManagerFactory positionManagerFactory;
    IUniswapAddressHolder uniswapAddressHolder;

    constructor(address _positionManagerFactory, address _uniswapAddressHolder) {
        positionManagerFactory = IPositionManagerFactory(_positionManagerFactory);
        uniswapAddressHolder = IUniswapAddressHolder(_uniswapAddressHolder);
    }

    ///@notice remove uniswap position NFT to the position manager
    ///@param tokenId ID of deposited token
    ///@param partToWithdraw percentage of token to withdraw in base points
    function withdrawUniNft(uint256 tokenId, uint256 partToWithdraw) external onlyOwner(tokenId) {
        require(
            partToWithdraw > 0 && partToWithdraw <= 10000,
            'WithdrawRecipes::withdrawUniNft: part to withdraw must be between 0 and 10000'
        );
        if (partToWithdraw == 10000) {
            IClosePosition(positionManagerFactory.userToPositionManager(msg.sender)).closePosition(
                tokenId,
                true ///@dev return the tokens to the user
            );
        } else {
            // 1. get position size
            // 2. divide for part to withdraw
            (uint256 amount0, uint256 amount1) = UniswapNFTHelper._getAmountsfromTokenId(
                tokenId,
                INonfungiblePositionManager(uniswapAddressHolder.nonfungiblePositionManagerAddress()),
                uniswapAddressHolder.uniswapV3FactoryAddress()
            );
            IDecreaseLiquidity(positionManagerFactory.userToPositionManager(msg.sender)).decreaseLiquidity(
                tokenId,
                (amount0 * partToWithdraw) / 10000,
                (amount1 * partToWithdraw) / 10000
            );
            ICollectFees(positionManagerFactory.userToPositionManager(msg.sender)).collectFees(tokenId, true);
        }
    }

    ///@notice remove a position from positionmanager zapping out
    ///@param tokenId ID of the token to withdraw
    ///@param tokenOut address of the token to withdraw
    function zapOutUniNft(uint256 tokenId, address tokenOut) external onlyOwner(tokenId) {
        IZapOut(positionManagerFactory.userToPositionManager(msg.sender)).zapOut(tokenId, tokenOut);
    }

    modifier onlyOwner(uint256 tokenId) {
        require(
            positionManagerFactory.userToPositionManager(msg.sender) ==
                INonfungiblePositionManager(uniswapAddressHolder.nonfungiblePositionManagerAddress()).ownerOf(tokenId), "WithdrawRecipes::onlyOwner: Only owner can call this function"
        );
        _;
    }
}
