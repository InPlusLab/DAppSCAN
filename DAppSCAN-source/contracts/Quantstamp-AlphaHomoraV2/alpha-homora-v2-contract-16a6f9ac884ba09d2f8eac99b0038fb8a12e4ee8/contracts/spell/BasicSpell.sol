pragma solidity 0.6.12;

import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC20/IERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC20/SafeERC20.sol';

import '../utils/ERC1155NaiveReceiver.sol';
import '../../interfaces/IBank.sol';
import '../../interfaces/IWERC20.sol';
import '../../interfaces/IWETH.sol';

contract BasicSpell is ERC1155NaiveReceiver {
  using SafeERC20 for IERC20;

  IBank public bank;
  IWERC20 public werc20;
  address public weth;

  mapping(address => mapping(address => bool)) public approved;

  constructor(
    IBank _bank,
    address _werc20,
    address _weth
  ) public {
    bank = _bank;
    werc20 = IWERC20(_werc20);
    weth = _weth;
    ensureApprove(_weth, address(_bank));
    werc20.setApprovalForAll(address(bank), true);
  }

  /// @dev Ensure that the spell approve the given spender to spend all of its tokens.
  /// @param token The token to approve.
  /// @param spender The spender to allow spending.
  /// NOTE: This is safe because spell is never built to hold fund custody.
  function ensureApprove(address token, address spender) public {
    if (!approved[token][spender]) {
      IERC20(token).safeApprove(spender, uint(-1));
      approved[token][spender] = true;
    }
  }

  /// @dev Internal call to convert msg.value ETH to WETH inside the contract.
  function doTransmitETH() internal {
    if (msg.value > 0) {
      IWETH(weth).deposit{value: msg.value}();
    }
  }

  /// @dev Internal call to transmit tokens from the bank if amount is positive.
  /// @param token The token to perform the transmit action.
  /// @param amount The amount to transmit.
  function doTransmit(address token, uint amount) internal {
    if (amount > 0) {
      bank.transmit(token, amount);
    }
  }

  /// @dev Internal call to refund tokens to the current bank executor.
  /// @param token The token to perform the refund action.
  function doRefund(address token) internal {
    uint balance = IERC20(token).balanceOf(address(this));
    if (balance > 0) {
      IERC20(token).safeTransfer(bank.EXECUTOR(), balance);
    }
  }

  /// @dev Internal call to refund all WETH to the current executor as native ETH.
  function doRefundETH() internal {
    uint balance = IWETH(weth).balanceOf(address(this));
    if (balance > 0) {
      IWETH(weth).withdraw(balance);
      (bool success, ) = bank.EXECUTOR().call{value: balance}(new bytes(0));
      require(success, 'refund ETH failed');
    }
  }

  /// @dev Internal call to borrow tokens from the bank on behalf of the current executor.
  /// @param token The token to borrow from the bank.
  /// @param amount The amount to borrow.
  function doBorrow(address token, uint amount) internal {
    if (amount > 0) {
      bank.borrow(token, amount);
    }
  }

  /// @dev Internal call to repay tokens to the bank on behalf of the current executor.
  /// @param token The token to repay to the bank.
  /// @param amount The amount to repay.
  function doRepay(address token, uint amount) internal {
    if (amount > 0) {
      ensureApprove(token, address(bank));
      bank.repay(token, amount);
    }
  }

  /// @dev Internal call to put collateral tokens to the bank.
  /// @param amount The amount to put to the bank.
  function doPutCollateral(address token, uint amount) internal {
    if (amount > 0) {
      ensureApprove(token, address(werc20));
      werc20.mint(token, amount);
      bank.putCollateral(address(werc20), uint(token), amount);
    }
  }

  /// @dev Internal call to take collateral tokens bank from the bank.
  /// @param amount The amount to take back.
  function doTakeCollateral(address token, uint amount) internal {
    if (amount > 0) {
      if (amount == uint(-1)) {
        (, , , amount) = bank.getPositionInfo(bank.POSITION_ID());
      }
      bank.takeCollateral(address(werc20), uint(token), amount);
      werc20.burn(token, amount);
    }
  }

  receive() external payable {
    require(msg.sender == weth, 'ETH must come from WETH');
  }
}
