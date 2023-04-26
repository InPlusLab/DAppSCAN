// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '../helpers/ERC20Helper.sol';
import '../helpers/UniswapNFTHelper.sol';
import '../utils/Storage.sol';
import '../../interfaces/actions/IIncreaseLiquidity.sol';

///@notice action to increase the liquidity of a V3 position
contract IncreaseLiquidity is IIncreaseLiquidity {
    ///@notice emitted when liquidity is increased
    ///@param positionManager address of the position manager which increased liquidity
    ///@param tokenId id of the position
    event LiquidityIncreased(address indexed positionManager, uint256 tokenId);

    ///@notice increase the liquidity of a UniswapV3 position
    ///@param tokenId the id of the position token
    ///@param amount0Desired the desired amount of token0
    ///@param amount1Desired the desired amount of token1
    function increaseLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) public override {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();

        require(
            amount0Desired > 0 || amount1Desired > 0,
            'IncreaseLiquidity::increaseLiquidity: Amounts cannot be both zero'
        );

        (address token0Address, address token1Address, , , ) = UniswapNFTHelper._getTokens(
            tokenId,
            INonfungiblePositionManager(Storage.uniswapAddressHolder.nonfungiblePositionManagerAddress())
        );

        ERC20Helper._approveToken(
            token0Address,
            Storage.uniswapAddressHolder.nonfungiblePositionManagerAddress(),
            amount0Desired
        );
        ERC20Helper._approveToken(
            token1Address,
            Storage.uniswapAddressHolder.nonfungiblePositionManagerAddress(),
            amount1Desired
        );

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 120
            });
        INonfungiblePositionManager(Storage.uniswapAddressHolder.nonfungiblePositionManagerAddress()).increaseLiquidity(
                params
            );

        emit LiquidityIncreased(address(this), tokenId);
    }
}
