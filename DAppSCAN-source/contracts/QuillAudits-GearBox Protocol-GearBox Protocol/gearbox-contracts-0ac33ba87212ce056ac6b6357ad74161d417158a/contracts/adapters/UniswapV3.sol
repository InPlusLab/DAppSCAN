// SPDX-License-Identifier: MIT
// Gearbox. Generalized leverage protocol that allows to take leverage and then use it across other DeFi protocols and platforms in a composable way.
// (c) Gearbox.fi, 2021
pragma solidity ^0.7.4;
pragma abicoder v2;

import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {ISwapRouter} from "../integrations/uniswap/IUniswapV3.sol";
import {BytesLib} from "../integrations/uniswap/BytesLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICreditFilter} from "../interfaces/ICreditFilter.sol";
import {ICreditManager} from "../interfaces/ICreditManager.sol";
import {CreditManager} from "../credit/CreditManager.sol";

import "hardhat/console.sol";

/// @title UniswapV3 Router adapter
contract UniswapV3Adapter is ISwapRouter {
    using BytesLib for bytes;
    using SafeMath for uint256;

    ICreditManager public creditManager;
    ICreditFilter public creditFilter;
    address public swapContract;

    /// @dev The length of the bytes encoded address
    uint256 private constant ADDR_SIZE = 20;

    /// @dev Constructor
    /// @param _creditManager Address Credit manager
    /// @param _swapContract Address of swap contract
    constructor(address _creditManager, address _swapContract) {
        creditManager = ICreditManager(_creditManager);
        creditFilter = ICreditFilter(creditManager.creditFilter());
        swapContract = _swapContract;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        // SWC-107-Reentrancy: L52
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        );

        creditManager.provideCreditAccountAllowance(
            creditAccount,
            swapContract,
            params.tokenIn
        );

        ExactInputSingleParams memory paramsUpdate = params;
        paramsUpdate.recipient = creditAccount;

        // 0x414bf389 = exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))
        bytes memory data = abi.encodeWithSelector(
            bytes4(0x414bf389), // +
            paramsUpdate
        );

        uint256 balanceBefore = IERC20(paramsUpdate.tokenIn).balanceOf(
            creditAccount
        );

        // ToDo: Check for partial execution
        bytes memory result = creditManager.executeOrder(
            msg.sender,
            swapContract,
            data
        );
        (amountOut) = abi.decode(result, (uint256));

        creditFilter.checkCollateralChange(
            creditAccount,
            params.tokenIn,
            params.tokenOut,
            balanceBefore.sub(
                IERC20(paramsUpdate.tokenIn).balanceOf(creditAccount)
            ),
            amountOut
        );
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInput(ExactInputParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        // SWC-107-Reentrancy: L106
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        );

        // SWC-124-Write to Arbitrary Storage Location: L105
        (address tokenIn, address tokenOut) = _extractTokens(params.path);

        creditManager.provideCreditAccountAllowance(
            creditAccount,
            swapContract,
            tokenIn
        );

        ExactInputParams memory paramsUpdate = params;
        paramsUpdate.recipient = creditAccount;

        // 0xc04b8d59 = exactInput((bytes,address,uint256,uint256,uint256))
        bytes memory data = abi.encodeWithSelector(
            bytes4(0xc04b8d59), // +
            paramsUpdate
        );

        uint256 balanceBefore = IERC20(tokenIn).balanceOf(creditAccount);

        bytes memory result = creditManager.executeOrder(
            msg.sender,
            swapContract,
            data
        );
        (amountOut) = abi.decode(result, (uint256));

        creditFilter.checkCollateralChange(
            creditAccount,
            tokenIn,
            tokenOut,
            balanceBefore.sub(IERC20(tokenIn).balanceOf(creditAccount)),
            amountOut
        );
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactOutputSingleParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        // SWC-107-Reentrancy: L153
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        );

        // SWC-107-Reentrancy: L154
        creditManager.provideCreditAccountAllowance(
            creditAccount,
            swapContract,
            params.tokenIn
        );

        ExactOutputSingleParams memory paramsUpdate = params;
        paramsUpdate.recipient = creditAccount;

        //
        bytes memory data = abi.encodeWithSelector(
            bytes4(0xdb3e2198), //+
            paramsUpdate
        );

        uint256 balanceBefore = IERC20(paramsUpdate.tokenOut).balanceOf(
            creditAccount
        );

        bytes memory result = creditManager.executeOrder(
            msg.sender,
            swapContract,
            data
        );
        (amountIn) = abi.decode(result, (uint256));

        creditFilter.checkCollateralChange(
            creditAccount,
            params.tokenIn,
            params.tokenOut,
            amountIn,
            IERC20(paramsUpdate.tokenOut).balanceOf(creditAccount).sub(
                balanceBefore
            )
        );
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactOutputParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutput(ExactOutputParams calldata params)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        address creditAccount = creditManager.getCreditAccountOrRevert(
            msg.sender
        );

        // SWC-124-Write to Arbitrary Storage Location: L206
        (address tokenOut, address tokenIn) = _extractTokens(params.path);

        console.log(tokenIn);
        console.log(tokenOut);

        // SWC-107-Reentrancy: L210
        creditManager.provideCreditAccountAllowance(
            creditAccount,
            swapContract,
            tokenIn
        );

        ExactOutputParams memory paramsUpdate = params;
        paramsUpdate.recipient = creditAccount;

        bytes memory data = abi.encodeWithSelector(
            bytes4(0xf28c0498), // exactOutput((bytes,address,uint256,uint256,uint256))
            paramsUpdate
        );

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(creditAccount);

        {
            bytes memory result = creditManager.executeOrder(
                msg.sender,
                swapContract,
                data
            );
            (amountIn) = abi.decode(result, (uint256));
        }

        console.log("balanceBefore");
        console.log(balanceBefore);
        console.log(IERC20(tokenOut).balanceOf(creditAccount));

        creditFilter.checkCollateralChange(
            creditAccount,
            tokenIn,
            tokenOut,
            amountIn,
            IERC20(tokenOut).balanceOf(creditAccount).sub(balanceBefore)
        );
    }

    function _extractTokens(bytes memory path)
        internal
        pure
        returns (address tokenA, address tokenB)
    {
        tokenA = path.toAddress(0);
        tokenB = path.toAddress(path.length - ADDR_SIZE);
    }
}
