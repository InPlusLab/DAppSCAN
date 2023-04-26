// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IAngleRouter.sol";
import "../interfaces/external/uniswap/IUniswapRouter.sol";
import "../interfaces/external/lido/IWStETH.sol";

contract MockRouter is IAngleRouter, IUniswapV3Router, IWStETH {
    using SafeERC20 for IERC20;

    uint256 public counterAngleMint;
    uint256 public counterAngleBurn;
    uint256 public counter1Inch;
    uint256 public counterUni;
    uint256 public counterWrap;
    uint256 public amountOutUni;
    uint256 public multiplierMintBurn;
    uint256 public stETHMultiplier;
    address public inToken;
    address public outToken;

    address public stETH;

    constructor() {}

    function mint(
        address user,
        uint256 amount,
        uint256,
        address stablecoin,
        address collateral
    ) external {
        counterAngleMint += 1;
        IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(stablecoin).safeTransfer(user, (amount * 10**9) / multiplierMintBurn);
    }

    function setStETH(address _stETH) external {
        stETH = _stETH;
    }

    function burn(
        address user,
        uint256 amount,
        uint256,
        address stablecoin,
        address collateral
    ) external {
        counterAngleBurn += 1;
        IERC20(stablecoin).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(collateral).safeTransfer(user, (amount * multiplierMintBurn) / 10**9);
    }

    function wrap(uint256 amount) external returns (uint256 amountOut) {
        amountOut = (amount * stETHMultiplier) / 10**9;
        counterWrap += 1;
        IERC20(stETH).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(outToken).safeTransfer(msg.sender, amountOut);
    }

    function oneInch(uint256 amountIn) external returns (uint256 amountOut) {
        counter1Inch += 1;
        amountOut = (amountOutUni * amountIn) / 10**9;
        IERC20(inToken).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(outToken).safeTransfer(msg.sender, amountOut);
    }

    function oneInchReverts() external {
        counter1Inch += 1;
        revert("wrong swap");
    }

    function oneInchRevertsWithoutMessage() external {
        counter1Inch += 1;
        require(false);
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut) {
        counterUni += 1;
        amountOut = (params.amountIn * amountOutUni) / 10**9;
        IERC20(inToken).safeTransferFrom(msg.sender, address(this), params.amountIn);
        IERC20(outToken).safeTransfer(params.recipient, amountOut);
        require(amountOut >= params.amountOutMinimum);
    }

    function setMultipliers(uint256 a, uint256 b) external {
        amountOutUni = a;
        multiplierMintBurn = b;
    }

    function setStETHMultiplier(uint256 value) external {
        stETHMultiplier = value;
    }

    function setInOut(address _collateral, address _stablecoin) external {
        inToken = _collateral;
        outToken = _stablecoin;
    }
}
