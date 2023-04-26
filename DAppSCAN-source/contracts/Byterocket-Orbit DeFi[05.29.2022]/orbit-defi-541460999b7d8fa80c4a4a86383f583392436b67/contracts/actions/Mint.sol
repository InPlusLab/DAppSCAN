// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '../helpers/ERC20Helper.sol';
import '../utils/Storage.sol';
import '../../interfaces/IPositionManager.sol';
import '../../interfaces/actions/IMint.sol';

///@notice action to mint a UniswapV3 position NFT
contract Mint is IMint {
    ///@notice emitted when a UniswapNFT is deposited in PositionManager
    ///@param positionManager address of PositionManager
    ///@param tokenId Id of deposited token
    event PositionMinted(address indexed positionManager, uint256 tokenId);

    ///@notice mints a UniswapV3 position NFT
    ///@param inputs struct of MintInput parameters
    ///@return tokenId ID of the minted NFT
    ///@return amount0Deposited token0 amount deposited
    ///@return amount1Deposited token1 amount deposited
    function mint(MintInput calldata inputs)
        public
        override
        returns (
            uint256 tokenId,
            uint256 amount0Deposited,
            uint256 amount1Deposited
        )
    {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();

        ERC20Helper._approveToken(
            inputs.token0Address,
            Storage.uniswapAddressHolder.nonfungiblePositionManagerAddress(),
            inputs.amount0Desired
        );
        ERC20Helper._approveToken(
            inputs.token1Address,
            Storage.uniswapAddressHolder.nonfungiblePositionManagerAddress(),
            inputs.amount1Desired
        );

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: inputs.token0Address,
            token1: inputs.token1Address,
            fee: inputs.fee,
            tickLower: inputs.tickLower,
            tickUpper: inputs.tickUpper,
            amount0Desired: inputs.amount0Desired,
            amount1Desired: inputs.amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 120
        });

        (tokenId, , amount0Deposited, amount1Deposited) = INonfungiblePositionManager(
            Storage.uniswapAddressHolder.nonfungiblePositionManagerAddress()
        ).mint(params);

        IPositionManager(address(this)).middlewareDeposit(tokenId);
        emit PositionMinted(address(this), tokenId);
    }
}
