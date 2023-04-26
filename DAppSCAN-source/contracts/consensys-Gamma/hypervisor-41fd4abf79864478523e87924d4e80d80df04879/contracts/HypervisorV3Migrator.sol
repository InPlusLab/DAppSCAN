// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';

import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

import './interfaces/IHypervisor.sol';
import './interfaces/IUniProxy.sol';

/// @title HperVisor V3 Migrator

contract HypervisorV3Migrator {
    using SafeMath for uint256;
    
    IUniswapV2Factory public uniswapV2Factory;
    IUniProxy public uniProxy;

    constructor(address _uniswapV2Factory, address _uniProxy) {
        uniswapV2Factory = IUniswapV2Factory(_uniswapV2Factory);
        uniProxy = IUniProxy(_uniProxy);
    }

    function migrate(address _hypervisor, uint8 percentageToMigrate, address recipient) external override {
        require(percentageToMigrate > 0, 'Percentage too small');
        require(percentageToMigrate <= 100, 'Percentage too large');

        // get v3 pair
        IHypervisor hypervisor = IHypervisor(_hypervisor);

        // get v2 pair from token0 & token1
        address v2Pair = uniswapV2Factory.getPair(address(hypervisor.token0()), address(hypervisor.token1()));
        uint256 balanceV2 = IUniswapV2Pair(v2Pair).balanceOf(msg.sender);
        require(balanceV2 > 0, 'No V2 liquidity');

        // burn v2 liquidity to this address
        IUniswapV2Pair(v2Pair).transferFrom(msg.sender, v2Pair, balanceV2);
        (uint256 amount0V2, uint256 amount1V2) = IUniswapV2Pair(v2Pair).burn(address(this));

        // calculate the amounts to migrate to v3
        uint256 amount1V2ToMigrate = amount1V2.mul(percentageToMigrate) / 100;
        uint256 amount0V2ToMigrate;
        ( , amount0V2ToMigrate) = uniProxy.getDepositAmount(address(address(hypervisor.token1())), amount1V2ToMigrate); 

        // approve the position manager up to the maximum token amounts
        TransferHelper.safeApprove(address(hypervisor.token0()), _hypervisor, amount0V2ToMigrate);
        TransferHelper.safeApprove(address(hypervisor.token1()), _hypervisor, amount1V2ToMigrate);

        // deposit to hypervisor through uniProxy
        uniProxy.deposit(
            amount0V2ToMigrate,
            amount1V2ToMigrate,
            recipient,
            msg.sender,
            _hypervisor
        );

        // if necessary, clear allowance and refund dust
    
        TransferHelper.safeApprove(address(hypervisor.token0()), _hypervisor, 0);
    
        uint256 refund0 = amount0V2 - amount0V2ToMigrate;
        if (refund0 > 0) {
            TransferHelper.safeTransfer(address(hypervisor.token0()), msg.sender, refund0);
        }

        TransferHelper.safeApprove(address(hypervisor.token1()), _hypervisor, 0);

        uint256 refund1 = amount1V2 - amount1V2ToMigrate;
        if (refund1 > 0) {
            TransferHelper.safeTransfer(address(hypervisor.token1()), msg.sender, refund1);
        }
    }
}
