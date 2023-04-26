pragma solidity 0.6.12;

import '../Governable.sol';
import '../../interfaces/IBaseOracle.sol';

contract SimpleOracle is IBaseOracle, Governable {
  mapping(address => uint) public prices; // Mapping from token to price in ETH (times 2**112).

  /// The governor sets oracle price for a token.
  event SetETHPx(address token, uint px);

  /// @dev Create the contract and initialize the first governor.
  constructor() public {
    Governable.initialize();
  }

  /// @dev Return the value of the given input as ETH per unit, multiplied by 2**112.
  /// @param token The ERC-20 token to check the value.
  function getETHPx(address token) external override view returns (uint) {
    return prices[token];
  }

  /// @dev Set the prices of the given token addresses.
  /// @param tokens The token addresses to set the prices.
  /// @param pxs The price data points, representing token value in ETH times 2**112.
  function setETHPx(address[] memory tokens, uint[] memory pxs) external onlyGov {
    require(tokens.length == pxs.length, 'inconsistent length');
    for (uint idx = 0; idx < tokens.length; idx++) {
      prices[tokens[idx]] = pxs[idx];
    }
  }
}
