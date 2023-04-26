pragma solidity >=0.4.21 <0.6.0;

import "../utils/Ownable.sol";
import "../erc20/IERC20.sol";
import "../core/IPool.sol";
import "./TestERC20.sol";
import "../utils/SafeMath.sol";
import "../erc20/SafeERC20.sol";
import "../erc20/TokenInterface.sol";


contract TestUSDCPool2 is ICurvePool{
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  address public target_addr;

  uint256 public total_amount;
  address public lp_addr;
  address public crv;
  constructor(address _target_addr, address _crv) public{
    name = "TestPool2";
    target_addr = _target_addr;
    lp_addr = address(new TestERC20("LP Token", 18, "LTN"));
    crv = _crv;
  }
  function deposit(uint256 _amount) public{
    uint256 t = _amount.safeMul(uint256(10) ** 18).safeDiv(uint256(10) ** ERC20Base(target_addr).decimals());
    total_amount = total_amount + t;
    IERC20(target_addr).safeTransferFrom(msg.sender, address(this), _amount);
    TokenInterface(lp_addr).generateTokens(address(this), t);
  }

  event LogT(uint256 value);
  function withdraw(uint256 _amount) public{
    total_amount = total_amount - _amount;
    TokenInterface(lp_addr).destroyTokens(address(this), _amount);
    _amount = _amount.safeMul(uint256(10) **ERC20Base(target_addr).decimals()).safeDiv(uint256(10)** 18);
    emit LogT(_amount);
    IERC20(target_addr).safeTransfer(msg.sender, _amount);
  }

  function get_virtual_price() public view returns(uint256){
    return 1000000000000000000;
  }

  function get_lp_token_balance() public view returns(uint256){
    return total_amount;
  }

  function get_lp_token_addr() public view returns(address){
    return lp_addr;
  }

  function earn_crv() public{
    TokenInterface(crv).generateTokens(address(this), uint256(10)**ERC20Base(crv).decimals());
    IERC20(crv).transfer(msg.sender, ERC20Base(crv).balanceOf(address(this)));
  }

}
