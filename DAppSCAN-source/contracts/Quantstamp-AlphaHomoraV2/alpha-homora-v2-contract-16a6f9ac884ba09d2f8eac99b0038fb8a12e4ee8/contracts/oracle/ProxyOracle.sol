pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/math/SafeMath.sol';

import '../Governable.sol';
import '../../interfaces/IOracle.sol';
import '../../interfaces/IBaseOracle.sol';
import '../../interfaces/IERC20Wrapper.sol';

contract ProxyOracle is IOracle, Governable {
  using SafeMath for uint;

  /// The governor sets oracle information for a token.
  event SetOracle(address token, Oracle info);
  /// The governor sets token whitelist for an ERC1155 token.
  event SetWhitelist(address token, bool ok);

  struct Oracle {
    IBaseOracle source; // The address to query price data, or zero if not supported.
    uint16 borrowFactor; // The borrow factor for this token, multiplied by 1e4.
    uint16 collateralFactor; // The collateral factor for this token, multiplied by 1e4.
    uint16 liqIncentive; // The liquidation incentive, multiplied by 1e4.
  }

  mapping(address => Oracle) public oracles; // Mapping from token address to oracle info.
  mapping(address => bool) public whitelistERC1155;

  /// @dev Create the contract and initialize the first governor.
  constructor() public {
    Governable.initialize();
  }

  /// @dev Set oracle information for the given list of token addresses.
  function setOracles(address[] memory tokens, Oracle[] memory info) external onlyGov {
    require(tokens.length == info.length, 'inconsistent length');
    for (uint idx = 0; idx < tokens.length; idx++) {
      require(info[idx].borrowFactor >= 10000, 'borrow factor must be at least 100%');
      require(info[idx].collateralFactor <= 10000, 'collateral factor must be at most 100%');
      require(info[idx].liqIncentive >= 10000, 'incentive must be at least 100%');
      require(info[idx].liqIncentive <= 20000, 'incentive must be at most 200%');
      oracles[tokens[idx]] = info[idx];
      emit SetOracle(tokens[idx], info[idx]);
    }
  }

  /// @dev Set whitelist status for the given list of token addresses.
  function setWhitelistERC1155(address[] memory tokens, bool ok) external onlyGov {
    for (uint idx = 0; idx < tokens.length; idx++) {
      whitelistERC1155[tokens[idx]] = ok;
      emit SetWhitelist(tokens[idx], ok);
    }
  }

  /// @dev Return whether the oracle supports evaluating collateral value of the given token.
  function support(address token, uint id) external view override returns (bool) {
    if (!whitelistERC1155[token]) return false;
    address tokenUnderlying = IERC20Wrapper(token).getUnderlying(id);
    return address(oracles[tokenUnderlying].source) != address(0);
  }

  /// @dev Return the amount of token out as liquidation reward for liquidating token in.
  function convertForLiquidation(
    address tokenIn,
    address tokenOut,
    uint tokenOutId,
    uint amountIn
  ) external view override returns (uint) {
    require(whitelistERC1155[tokenOut], 'bad token');
    address tokenOutUnderlying = IERC20Wrapper(tokenOut).getUnderlying(tokenOutId);
    Oracle memory oracleIn = oracles[tokenIn];
    Oracle memory oracleOut = oracles[tokenOutUnderlying];
    uint amountOut =
      amountIn.mul(oracleIn.source.getETHPx(tokenIn)).div(
        oracleIn.source.getETHPx(tokenOutUnderlying)
      );
    return amountOut.mul(oracleIn.liqIncentive).mul(oracleOut.liqIncentive).div(10000 * 10000);
  }

  /// @dev Return the value of the given input as ETH for collateral purpose.
  function asETHCollateral(
    address token,
    uint id,
    uint amount
  ) external view override returns (uint) {
    require(whitelistERC1155[token], 'bad token');
    address tokenUnderlying = IERC20Wrapper(token).getUnderlying(id);
    Oracle memory oracle = oracles[tokenUnderlying];
    uint ethValue = oracle.source.getETHPx(tokenUnderlying).mul(amount).div(2**112);
    return ethValue.mul(oracle.collateralFactor).div(10000);
  }

  /// @dev Return the value of the given input as ETH for borrow purpose.
  function asETHBorrow(address token, uint amount) external view override returns (uint) {
    Oracle memory oracle = oracles[token];
    uint ethValue = oracle.source.getETHPx(token).mul(amount).div(2**112);
    return ethValue.mul(oracle.borrowFactor).div(10000);
  }
}
