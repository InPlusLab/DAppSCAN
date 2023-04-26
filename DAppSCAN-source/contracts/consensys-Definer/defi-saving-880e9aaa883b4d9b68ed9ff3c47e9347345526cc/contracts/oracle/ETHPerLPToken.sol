pragma solidity 0.5.14;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

interface mockERC20InterfaceLP{
    function balanceOf(address owner) external view returns (uint);
    function totalSupply() external view returns (uint256);
}

contract ETHPerLPToken {
    using SafeMath for uint256;
    
    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public FIN_LP = 0x486792bcdb13F8aaCf85288D98850FA2804F95c7;
    
    function latestAnswer() public view returns (int256){
        uint balance = mockERC20InterfaceLP(WETH).balanceOf(FIN_LP);
        uint totalSupply = mockERC20InterfaceLP(FIN_LP).totalSupply();
        return int(balance.mul(2).mul(10 ** 18).div(totalSupply));
    }
}