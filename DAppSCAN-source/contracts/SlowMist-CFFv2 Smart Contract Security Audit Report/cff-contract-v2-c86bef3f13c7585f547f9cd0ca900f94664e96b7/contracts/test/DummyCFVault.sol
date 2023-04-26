pragma solidity >=0.4.21 <0.6.0;

import "../utils/Ownable.sol";
import "../utils/SafeMath.sol";
import "../utils/Address.sol";
import "../utils/ReentrancyGuard.sol";
import "../utils/TransferableToken.sol";
import "../erc20/SafeERC20.sol";
import "../erc20/TokenInterface.sol";

contract DummyCFVault is Ownable{
  using SafeMath for uint;
  using SafeERC20 for IERC20;
  address public target_token;
  address public lp_token;
  constructor(address _target_token, address _lp_token) public {
    target_token = _target_token;
    lp_token = _lp_token;
  }
  function get_virtual_price() public view returns(uint256){
    return 1e18;
  }

  function withdraw(uint256 _amount) public{
    uint256 amount = IERC20(lp_token).balanceOf(msg.sender);
    require(amount >= _amount, "no enough LP tokens");

    uint LP_token_amount = _amount.safeMul(TransferableToken.balanceOfAddr(target_token, address(this))).safeDiv(IERC20(lp_token).totalSupply());

    TokenInterface(lp_token).destroyTokens(msg.sender, _amount);
    TransferableToken.transfer(target_token, msg.sender, LP_token_amount);
  }

  function deposit(uint256 _amount) public payable{
    if(target_token == address(0x0)){
      require(_amount == msg.value, "inconsist amount");
    }else{
      require(IERC20(target_token).allowance(msg.sender, address(this)) >= _amount, "CFVault: not enough allowance");
    }

    if(target_token != address(0x0)){
      IERC20(target_token).safeTransferFrom(msg.sender, address(this), _amount);
    }else{
      //TransferableToken.transfer(target_token, address(this).toPayable(), _amount);
    }

    uint dec = uint(10)**(TransferableToken.decimals(target_token));
    uint lp_dec = uint(10) **(TransferableToken.decimals(lp_token));

    uint lp_amount = _amount.safeMul(lp_dec).safeDiv(dec);
    TokenInterface(lp_token).generateTokens(msg.sender, lp_amount);
  }
}

contract DummyCFVaultFactory{
  event NewCFVault(address addr);

  function createCFVault(address _target_token, address _lp_token) public returns(address){
    DummyCFVault cf = new DummyCFVault(_target_token, _lp_token);
    cf.transferOwnership(msg.sender);
    emit NewCFVault(address(cf));
    return address(cf);
  }

}
