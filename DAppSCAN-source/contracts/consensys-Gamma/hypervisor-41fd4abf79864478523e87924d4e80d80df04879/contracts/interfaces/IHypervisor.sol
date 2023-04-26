// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IHypervisor {

    function deposit(
        uint256,
        uint256,
        address
    ) external returns (uint256);

    function deposit(
        uint256,
        uint256,
        address,
        address
    ) external returns (uint256);

    function withdraw(
        uint256,
        address,
        address
    ) external returns (uint256, uint256);


    function rebalance(
        int24 _baseLower,
        int24 _baseUpper,
        int24 _limitLower,
        int24 _limitUpper,
        address _feeRecipient,
        int256 swapQuantity
    ) external;

    function addBaseLiquidity(
      uint256 amount0, 
      uint256 amount1
    ) external;

    function addLimitLiquidity(
      uint256 amount0, 
      uint256 amount1
    ) external;   

    function pullLiquidity(uint256 shares)
    external returns(
        uint256 base0,
        uint256 base1,
        uint256 limit0,
        uint256 limit1
    );

    function pool() external view returns (IUniswapV3Pool);

    function currentTick() external view returns (int24 tick);

    function token0() external view returns (IERC20);

    function token1() external view returns (IERC20);

    function balanceOf(address) external view returns (uint256);

    function approve(address, uint256) external returns (bool);

    function transferFrom(address, address, uint256) external returns (bool);

    function transfer(address, uint256) external returns (bool);

    function getTotalAmounts() external view returns (uint256 total0, uint256 total1);

    function pendingFees() external returns (uint256 fees0, uint256 fees1);
    
    function totalSupply() external view returns (uint256 );

    function setMaxTotalSupply(uint256 _maxTotalSupply) external;

    function setDepositMax(uint256 _deposit0Max, uint256 _deposit1Max) external;

    function appendList(address[] memory listed) external;

    function toggleWhitelist() external;

    function transferOwnership(address newOwner) external;

}
