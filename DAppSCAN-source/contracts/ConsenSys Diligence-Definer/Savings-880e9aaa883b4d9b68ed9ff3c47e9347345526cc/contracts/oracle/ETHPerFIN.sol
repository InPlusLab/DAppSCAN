pragma solidity 0.5.14;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
// import "../config/Constant.sol";

interface mockERC20InterfaceFIN{
    function balanceOf(address owner) external view returns (uint);
}

contract ETHPerFIN {
    using SafeMath for uint256;
    
    // Constant public constants;
    
    address public FIN = 0x054f76beED60AB6dBEb23502178C52d6C5dEbE40;
    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public uniswap = 0x486792bcdb13F8aaCf85288D98850FA2804F95c7;
    
    function latestAnswer() public view returns (int256){
        uint balance0 = mockERC20InterfaceFIN(FIN).balanceOf(uniswap); // 383328811522809054672340
        uint balance1 = mockERC20InterfaceFIN(WETH).balanceOf(uniswap); // 646683755097326209560
        return int(balance1.mul(10 ** 18).div(balance0));
    }
}