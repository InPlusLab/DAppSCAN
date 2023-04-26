pragma solidity 0.6.12;

import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/math/SafeMath.sol';

import './BaseKP3ROracle.sol';
import '../utils/HomoraMath.sol';
import '../../interfaces/IBaseOracle.sol';
import '../../interfaces/IKeep3rV1Oracle.sol';
import '../../interfaces/IUniswapV2Pair.sol';

contract UniswapV2LPKP3ROracle is IBaseOracle, BaseKP3ROracle {
  using SafeMath for uint;
  using HomoraMath for uint;

  constructor(IKeep3rV1Oracle _kp3r) public BaseKP3ROracle(_kp3r) {}

  /// @dev Return the value of the given input as ETH per unit, multiplied by 2**112.
  /// @param pair The Uniswap pair to check the value.
  function getETHPx(address pair) external view override returns (uint) {
    address token0 = IUniswapV2Pair(pair).token0();
    uint totalSupply = IUniswapV2Pair(pair).totalSupply();
    (uint r0, uint r1, ) = IUniswapV2Pair(pair).getReserves();
    uint sqrtK = HomoraMath.sqrt(r0.mul(r1)).fdiv(totalSupply); // in 2**112
    uint twap = token0 < weth ? price0TWAP(pair) : price1TWAP(pair);
    uint value = 2 * sqrtK.fmul(HomoraMath.sqrt(twap)).fdiv(HomoraMath.sqrt(2**112));
    return value;
  }
}
