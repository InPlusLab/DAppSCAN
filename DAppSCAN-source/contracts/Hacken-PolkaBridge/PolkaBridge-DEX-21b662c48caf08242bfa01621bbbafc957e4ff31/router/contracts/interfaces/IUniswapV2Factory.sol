// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

interface IUniswapV2Factory {

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    event TreasurySet(address _address);
    

    function setTreasuryAddress(address _address) external;
    
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs() external view returns (uint);
    // function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

}
