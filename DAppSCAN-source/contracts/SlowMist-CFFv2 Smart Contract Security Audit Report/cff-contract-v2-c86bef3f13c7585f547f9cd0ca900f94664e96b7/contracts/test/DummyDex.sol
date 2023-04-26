pragma solidity >=0.4.21 <0.6.0;

import "../utils/Ownable.sol";
import "../erc20/IERC20.sol";
import "../erc20/ERC20Impl.sol";
import "../utils/SafeMath.sol";
import "../erc20/TokenInterface.sol";


contract DummyDex{
  using SafeMath for uint256;

  function getAmountsOut(uint256 amountIn, address[] memory path) public view returns(uint256[] memory){
    uint256[] memory k = new uint256[](path.length);
    for(uint i = 0; i < path.length; i ++){
      uint256 t = amountIn.safeMul(uint256(10)**ERC20Base(path[i]).decimals()).safeDiv(uint256(10) **ERC20Base(path[0]).decimals());
      k[i] = t;
    }
    return k;
  }
  function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] memory path, address to, uint256 deadline) public returns (uint256[] memory amounts) {
    uint256[] memory k = getAmountsOut(amountIn, path);
    IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
    TokenInterface(path[path.length - 1]).generateTokens(to, k[k.length - 1]);
    return k;
  }
}
