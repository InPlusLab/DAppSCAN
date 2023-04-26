// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import './BaseModule.sol';
import '../../interfaces/IPositionManager.sol';
import '../../interfaces/IRegistry.sol';
import '../../interfaces/IUniswapAddressHolder.sol';
import '../../interfaces/actions/ICollectFees.sol';
import '../../interfaces/actions/IIncreaseLiquidity.sol';
import '../../interfaces/actions/IUpdateUncollectedFees.sol';
import '../helpers/UniswapNFTHelper.sol';
import '../utils/Storage.sol';

contract AutoCompoundModule is BaseModule {
    IUniswapAddressHolder addressHolder;

    ///@notice constructor of autoCompoundModule
    ///@param _addressHolder the address of the uniswap address holder contract
    ///@param _registry the address of the registry contract
    constructor(address _addressHolder, address _registry) BaseModule(_registry) {
        addressHolder = IUniswapAddressHolder(_addressHolder);
        registry = IRegistry(_registry);
    }

    ///@notice executes our recipe for autocompounding
    ///@param positionManager address of the position manager
    ///@param tokenId id of the token to autocompound
    function autoCompoundFees(IPositionManager positionManager, uint256 tokenId)
        public
        onlyWhitelistedKeeper
        activeModule(address(positionManager), tokenId)
    {
        ///@dev check if compound need to be done
        if (_checkIfCompoundIsNeeded(address(positionManager), tokenId)) {
            (uint256 amount0Desired, uint256 amount1Desired) = ICollectFees(address(positionManager)).collectFees(
                tokenId,
                false
            );

            IIncreaseLiquidity(address(positionManager)).increaseLiquidity(tokenId, amount0Desired, amount1Desired);
        }
    }

    ///@notice checks the position status
    ///@param positionManagerAddress address of the position manager
    ///@param tokenId token id of the position
    ///@return true if the position needs to be collected
    function _checkIfCompoundIsNeeded(address positionManagerAddress, uint256 tokenId) internal returns (bool) {
        (uint256 uncollectedFees0, uint256 uncollectedFees1) = IUpdateUncollectedFees(positionManagerAddress)
            .updateUncollectedFees(tokenId);

        (uint256 amount0, uint256 amount1) = UniswapNFTHelper._getAmountsfromTokenId(
            tokenId,
            INonfungiblePositionManager(addressHolder.nonfungiblePositionManagerAddress()),
            addressHolder.uniswapV3FactoryAddress()
        );

        (, bytes32 data) = IPositionManager(positionManagerAddress).getModuleInfo(tokenId, address(this));

        uint256 feesThreshold = uint256(data);

        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(
            UniswapNFTHelper._getPoolFromTokenId(
                tokenId,
                INonfungiblePositionManager(addressHolder.nonfungiblePositionManagerAddress()),
                addressHolder.uniswapV3FactoryAddress()
            )
        ).slot0();
        //returns true if the value of uncollected fees * 100 is greater than amount in the position * threshold
        return (((uncollectedFees0 * sqrtPriceX96) / 2**96 + (uncollectedFees1 * 2**96) / sqrtPriceX96) * 100 >
            ((amount0 * sqrtPriceX96) / 2**96 + (amount1 * 2**96) / sqrtPriceX96) * feesThreshold);
    }
}
