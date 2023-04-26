// SPDX-License-Identifier: MIT
pragma solidity >=0.8.7 <0.9.0;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol';

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import './Governable.sol';

library Math {
  function max(uint256 a, uint256 b) internal pure returns (uint256) {
    return a >= b ? a : b;
  }

  function min(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }
}

interface IKeep3rV1 {
  function totalBonded() external view returns (uint256);

  function bonds(address keeper, address credit) external view returns (uint256);

  function votes(address keeper) external view returns (uint256);
}

contract Keep3rV3Helper is Governable {
  using EnumerableSet for EnumerableSet.AddressSet;

  event TWAPSet(uint32 twapPeriod);

  error ZeroAddress();
  error InvalidTWAP();

  uint256 public constant MIN = 11;
  uint256 public constant MAX = 12;
  uint256 public constant BASE = 10;
  uint256 public constant SWAP = 300_000;
  uint256 public constant ORACLE_QUOTE = 25_000;
  uint256 public constant TARGETBOND = 200e18;

  /* solhint-disable var-name-mixedcase */
  IKeep3rV1 public immutable KP3R;
  address public immutable WETH;
  address public immutable POOL;
  /* solhint-disable var-name-mixedcase */

  uint32 public twapPeriod = 2 minutes;

  constructor(
    address _governor,
    IKeep3rV1 _KP3R,
    address _WETH,
    address _POOL
  ) Governable(_governor) {
    if (address(_KP3R) == address(0) || address(_WETH) == address(0) || address(_POOL) == address(0)) revert ZeroAddress();
    KP3R = _KP3R;
    WETH = _WETH;
    POOL = _POOL;
  }

  function setTWAPPeriod(uint32 _twapPeriod) public onlyGovernor {
    if (_twapPeriod == 0) revert InvalidTWAP();
    twapPeriod = _twapPeriod;
    emit TWAPSet(_twapPeriod);
  }

  function getQuote(uint128 _amountIn) public view returns (uint256 _amountOut) {
    _amountOut = OracleLibrary.getQuoteAtTick(OracleLibrary.consult(POOL, twapPeriod), _amountIn, WETH, address(KP3R));
  }

  function bonds(address keeper) public view returns (uint256) {
    return KP3R.bonds(keeper, address(KP3R)) + (KP3R.votes(keeper));
  }

  function _getBasefee() internal view virtual returns (uint256) {
    return block.basefee;
  }

  function getQuoteLimitFor(address _origin, uint256 _gasUsed) public view returns (uint256) {
    uint256 quote = getQuote(uint128((_gasUsed + SWAP + ORACLE_QUOTE) * _getBasefee()));
    uint256 min = (quote * MIN) / BASE;
    uint256 boost = (quote * MAX) / BASE;
    uint256 bond = Math.min(bonds(_origin), TARGETBOND);
    return Math.max(min, (boost * bond) / TARGETBOND);
  }

  function getQuoteLimit(uint256 gasUsed) external view returns (uint256) {
    // solhint-disable-next-line avoid-tx-origin
    return getQuoteLimitFor(tx.origin, gasUsed);
  }
}
