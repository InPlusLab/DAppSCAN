pragma solidity 0.6.12;

import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC1155/ERC1155.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC20/IERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC20/SafeERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/utils/ReentrancyGuard.sol';

import '../../interfaces/IWERC20.sol';

contract WERC20 is ERC1155('WERC20'), ReentrancyGuard, IWERC20 {
  using SafeERC20 for IERC20;

  /// @dev Return the underlying ERC-20 for the given ERC-1155 token id.
  function getUnderlying(uint id) external view override returns (address) {
    address token = address(id);
    require(uint(token) == id, 'id overflow');
    return token;
  }

  /// @dev Return the underlying ERC20 balance for the user.
  function balanceOfERC20(address token, address user) external view override returns (uint) {
    return balanceOf(user, uint(token));
  }

  /// @dev Mint ERC1155 token for the given ERC20 token.
  function mint(address token, uint amount) external override nonReentrant {
    uint balanceBefore = IERC20(token).balanceOf(address(this));
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    uint balanceAfter = IERC20(token).balanceOf(address(this));
    _mint(msg.sender, uint(token), balanceAfter.sub(balanceBefore), '');
  }

  /// @dev Burn ERC1155 token to redeem ERC20 token back.
  function burn(address token, uint amount) external override nonReentrant {
    _burn(msg.sender, uint(token), amount);
    IERC20(token).safeTransfer(msg.sender, amount);
  }
}
