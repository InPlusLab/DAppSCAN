pragma solidity 0.6.12;

interface IERC20Wrapper {
  /// @dev Return the underlying ERC-20 for the given ERC-1155 token id.
  function getUnderlying(uint id) external view returns (address);
}
