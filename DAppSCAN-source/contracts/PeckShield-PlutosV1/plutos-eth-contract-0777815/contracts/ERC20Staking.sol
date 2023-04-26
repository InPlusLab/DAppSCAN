pragma solidity >=0.4.21 <0.6.0;
import "../utils/Ownable.sol";
import "../assets/TokenBankInterface.sol";
import "../erc20/TokenInterface.sol";
import "../erc20/IERC20.sol";
import "../erc20/SafeERC20.sol";
import "../utils/SafeMath.sol";
import "../erc20/ERC20Impl.sol";

contract ERC20StakingCallbackInterface{
  function onStake(address addr, uint256 target_amount, uint256 lp_amount) public returns(bool);
  function onClaim(address addr, uint256 target_amount, uint256 lp_amount) public returns(bool);
}

contract ERC20Staking is Ownable{
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public target_token;
  address public lp_token;

  ERC20StakingCallbackInterface public callback;

  constructor(address _target_token, address _lp_token) public{
    target_token = _target_token;
    lp_token = _lp_token;
    callback = ERC20StakingCallbackInterface(0x0);
  }

  event ERC20StakingChangeCallback(address _old, address _new);
  function changeCallback(address addr) public onlyOwner returns(bool){
    address old = address(callback);
    callback = ERC20StakingCallbackInterface(addr);
    emit ERC20StakingChangeCallback(old, addr);
    return true;
  }

  event ERC20Stake(address addr, uint256 target_amount, uint256 lp_amount);
  function stake(uint256 _amount) public returns(uint256){
    uint256 amount = 0;
    uint256 prev = IERC20(target_token).balanceOf(address(this));
    IERC20(target_token).safeTransferFrom(msg.sender, address(this), _amount);
    amount = IERC20(target_token).balanceOf(address(this)).safeSub(prev);

    if(amount == 0){
      return 0;
    }

    uint256 lp_amount = 0;
    {
      if(IERC20(lp_token).totalSupply() == 0){
        lp_amount = amount.safeMul(uint256(10)**ERC20Base(lp_token).decimals()).safeDiv(uint256(10)**ERC20Base(target_token).decimals());
      }else{
        uint256 t2 = IERC20(lp_token).totalSupply();
        lp_amount = amount.safeMul(t2).safeDiv(prev);
      }
    }
    if(lp_amount == 0){
      return 0;
    }

    TokenInterface(lp_token).generateTokens(msg.sender, lp_amount);

    if(address(callback) != address(0x0)){
      callback.onStake(msg.sender, amount, lp_amount);
    }

    emit ERC20Stake(msg.sender, amount, lp_amount);
    return lp_amount;
  }

  event ERC20Claim(address addr, uint256 target_amount, uint256 lp_amount);
  function claim(uint256 _amount) public returns(uint256){
    uint256 total = IERC20(lp_token).totalSupply();

    require(IERC20(lp_token).balanceOf(msg.sender) >= _amount, "not enough lp token to claim");
    TokenInterface(lp_token).destroyTokens(msg.sender, _amount);

    uint256 amount = 0;
    {
      if(IERC20(lp_token).totalSupply() == 0){
        amount = IERC20(target_token).balanceOf(address(this));
      }else{
        amount = _amount.safeMul(IERC20(target_token).balanceOf(address(this))).safeDiv(total);
      }
    }
    IERC20(target_token).safeTransfer(msg.sender, amount);

    if(address(callback) != address(0x0)){
      callback.onClaim(msg.sender, amount, _amount);
    }

    emit ERC20Claim(msg.sender, amount, _amount);

    return amount;
  }

  event ERC20IncreaseTargetToken(address addr, uint256 amount);
  //We add this method to keep interface clean
  function increase_target_token(uint256 _amount) public returns(bool){
    IERC20(target_token).safeTransferFrom(msg.sender, address(this), _amount);
    emit ERC20IncreaseTargetToken(msg.sender, _amount);
    return true;
  }

  function getPricePerFullShare() public view returns(uint256){
    return IERC20(target_token).balanceOf(address(this)).safeMul(1e18).safeMul(uint256(10)**ERC20Base(lp_token).decimals()).safeDiv(IERC20(lp_token).totalSupply()).safeDiv(uint256(10)**ERC20Base(target_token).decimals());
  }
}

contract ERC20StakingFactory{
  event NewERC20Staking(address addr);
  function createERC20Staking(address _target_token, address _lp_token) public returns(address){
    ERC20Staking s = new ERC20Staking(_target_token, _lp_token);
    emit NewERC20Staking(address(s));
    s.transferOwnership(msg.sender);
    return address(s);
  }
}
