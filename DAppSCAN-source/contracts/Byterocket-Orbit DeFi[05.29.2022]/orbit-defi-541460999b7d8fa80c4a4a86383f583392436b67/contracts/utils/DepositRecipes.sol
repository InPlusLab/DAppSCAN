// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import '../../interfaces/actions/IMint.sol';
import '../../interfaces/actions/IZapIn.sol';
import '../../interfaces/IPositionManager.sol';
import '../../interfaces/IPositionManagerFactory.sol';
import '../../interfaces/IUniswapAddressHolder.sol';

///@notice DepositRecipes allows user to fill their position manager with UniswapV3 positions
///        by depositing an already minted NFT or by minting directly a new one
contract DepositRecipes {
    IUniswapAddressHolder uniswapAddressHolder;
    IPositionManagerFactory positionManagerFactory;

    constructor(address _uniswapAddressHolder, address _positionManagerFactory) {
        uniswapAddressHolder = IUniswapAddressHolder(_uniswapAddressHolder);
        positionManagerFactory = IPositionManagerFactory(_positionManagerFactory);
    }

    ///@notice emitted when a position is created
    ///@param positionManager the address of the position manager which recieved the position
    ///@param from address of the user
    ///@param tokenId ID of the minted NFT
    event PositionDeposited(address indexed positionManager, address from, uint256 tokenId);

    ///@notice add uniswap position NFT to the position manager
    ///@param tokenIds IDs of deposited tokens
    function depositUniNft(uint256[] calldata tokenIds) external {
        address positionManagerAddress = positionManagerFactory.userToPositionManager(msg.sender);

        for (uint32 i = 0; i < tokenIds.length; i++) {
            INonfungiblePositionManager(uniswapAddressHolder.nonfungiblePositionManagerAddress()).safeTransferFrom(
                msg.sender,
                positionManagerAddress,
                tokenIds[i],
                '0x0'
            );
            IPositionManager(positionManagerAddress).middlewareDeposit(tokenIds[i]);
            emit PositionDeposited(positionManagerAddress, msg.sender, tokenIds[i]);
        }
    }

    ///@notice mint uniswapV3 NFT and deposit in the position manager
    ///@param token0 the first token to be deposited
    ///@param token1 the second token to be deposited
    ///@param fee fee tier of the pool to be deposited in
    ///@param tickLower the lower bound of the position range
    ///@param tickUpper the upper bound of the position range
    ///@param amount0Desired the amount of the first token to be deposited
    ///@param amount1Desired the amount of the second token to be deposited
    ///@return tokenId the ID of the minted NFT
    function mintAndDeposit(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external returns (uint256 tokenId) {
        address positionManagerAddress = positionManagerFactory.userToPositionManager(msg.sender);

        ///@dev send tokens to position manager to be able to call the mint action
        IERC20(token0).transferFrom(msg.sender, positionManagerAddress, amount0Desired);
        IERC20(token1).transferFrom(msg.sender, positionManagerAddress, amount1Desired);

        (tokenId, , ) = IMint(positionManagerAddress).mint(
            IMint.MintInput(token0, token1, fee, tickLower, tickUpper, amount0Desired, amount1Desired)
        );
    }

    ///@notice mints a uni NFT with a single input token, the token in input can be different from the two position tokens
    ///@param tokenIn address of input token
    ///@param amountIn amount of input token
    ///@param token0 address token0 of the pool
    ///@param token1 address token1 of the pool
    ///@param tickLower lower bound of desired position
    ///@param tickUpper upper bound of desired position
    ///@param fee fee tier of the pool
    ///@return tokenId of minted NFT
    function zapInUniNft(
        address tokenIn,
        uint256 amountIn,
        address token0,
        address token1,
        int24 tickLower,
        int24 tickUpper,
        uint24 fee
    ) external returns (uint256 tokenId) {
        address positionManagerAddress = positionManagerFactory.userToPositionManager(msg.sender);

        (tokenId) = IZapIn(positionManagerAddress).zapIn(tokenIn, amountIn, token0, token1, tickLower, tickUpper, fee);
    }
}
