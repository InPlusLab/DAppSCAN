pragma solidity 0.6.12;

import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC1155/IERC1155.sol';

import './IERC20Wrapper.sol';

interface IWERC20 is IERC1155, IERC20Wrapper {
  /// @dev Return the underlying ERC20 balance for the user.
  function balanceOfERC20(address token, address user) external view returns (uint);

  /// @dev Mint ERC1155 token for the given ERC20 token.
  function mint(address token, uint amount) external;

  /// @dev Burn ERC1155 token to redeem ERC20 token back.
  function burn(address token, uint amount) external;
}
