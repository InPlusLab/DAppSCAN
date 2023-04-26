// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import {IUniswapV3Factory} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

import {Hypervisor} from './Hypervisor.sol';

contract HypervisorFactory is Ownable {
    IUniswapV3Factory public uniswapV3Factory;
    mapping(address => mapping(address => mapping(uint24 => address))) public getHypervisor; // toke0, token1, fee -> hypervisor address
    address[] public allHypervisors;

    event HypervisorCreated(address token0, address token1, uint24 fee, address hypervisor, uint256);

    constructor(address _uniswapV3Factory) {
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
    }

    function allHypervisorsLength() external view returns (uint256) {
        return allHypervisors.length;
    }

    function createHypervisor(
        address tokenA,
        address tokenB,
        uint24 fee,
        string memory name,
        string memory symbol

    ) external onlyOwner returns (address hypervisor) {
        require(tokenA != tokenB, 'SF: IDENTICAL_ADDRESSES'); // TODO: using PoolAddress library (uniswap-v3-periphery)
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'SF: ZERO_ADDRESS');
        require(getHypervisor[token0][token1][fee] == address(0), 'SF: HYPERVISOR_EXISTS');
        int24 tickSpacing = uniswapV3Factory.feeAmountTickSpacing(fee);
        require(tickSpacing != 0, 'SF: INCORRECT_FEE');
        address pool = uniswapV3Factory.getPool(token0, token1, fee);
        if (pool == address(0)) {
            pool = uniswapV3Factory.createPool(token0, token1, fee);
        }
        hypervisor = address(
            new Hypervisor{salt: keccak256(abi.encodePacked(token0, token1, fee, tickSpacing))}(pool, owner(), name, symbol)
        );

        getHypervisor[token0][token1][fee] = hypervisor;
        getHypervisor[token1][token0][fee] = hypervisor; // populate mapping in the reverse direction
        allHypervisors.push(hypervisor);
        emit HypervisorCreated(token0, token1, fee, hypervisor, allHypervisors.length);
    }
}
