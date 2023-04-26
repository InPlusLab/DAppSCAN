pragma solidity 0.6.12;

interface IOracle {
  /// @dev Return whether the oracle supports evaluating collateral value of the given address.
  /// @param token The ERC-1155 token to check the acceptence.
  /// @param id The token id to check the acceptance.
  function support(address token, uint id) external view returns (bool);

  /// @dev Return the amount of token out as liquidation reward for liquidating token in.
  /// @param tokenIn The ERC-20 token that gets liquidated.
  /// @param tokenOut The ERC-1155 token to pay as reward.
  /// @param tokenOutId The id of the token to pay as reward.
  /// @param amountIn The amount of liquidating tokens.
  function convertForLiquidation(
    address tokenIn,
    address tokenOut,
    uint tokenOutId,
    uint amountIn
  ) external view returns (uint);

  /// @dev Return the value of the given input as ETH for collateral purpose.
  /// @param token The ERC-1155 token to check the value.
  /// @param id The id of the token to check the value.
  /// @param amount The amount of tokens to check the value.
  function asETHCollateral(
    address token,
    uint id,
    uint amount
  ) external view returns (uint);

  /// @dev Return the value of the given input as ETH for borrow purpose.
  /// @param token The ERC-20 token to check the value.
  /// @param amount The amount of tokens to check the value.
  function asETHBorrow(address token, uint amount) external view returns (uint);
}
