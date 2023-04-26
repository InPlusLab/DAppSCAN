pragma solidity >=0.4.21 <0.6.0;
import "../../utils/Ownable.sol";
import "../IPool.sol";
import "../../utils/TokenClaimer.sol";
import "../../erc20/IERC20.sol";
import "../../erc20/SafeERC20.sol";


contract PriceInterfaceWbtc{
  function get_virtual_price() public view returns(uint256);
}

contract IWbtcPoolBase is ICurvePool, Ownable{
  using SafeERC20 for IERC20;
  address public wbtc;

  address public controller;
  address public vault;
  address public lp_token_addr;

  uint256 public lp_balance;
  uint256 public deposit_wbtc_amount;
  uint256 public withdraw_wbtc_amount;

  modifier onlyController(){
    require((controller == msg.sender)||(vault == msg.sender), "only controller can call this");
    _;
  }

  constructor() public{
    wbtc = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
  }

  function deposit_wbtc(uint256 _amount) internal;

  //@_amount: USDC amount
  function deposit(uint256 _amount) public onlyController{
    deposit_wbtc_amount = deposit_wbtc_amount + _amount;
    deposit_wbtc(_amount);
    uint256 cur = IERC20(lp_token_addr).balanceOf(address(this));
    lp_balance = lp_balance + cur;
    IERC20(lp_token_addr).safeTransfer(msg.sender, cur);
  }

  function withdraw_from_curve(uint256 _amount) internal;

  //@_amount: lp token amount
  function withdraw(uint256 _amount) public onlyController{
    withdraw_from_curve(_amount);
    lp_balance = lp_balance - _amount;

    IERC20(wbtc).transfer(msg.sender, IERC20(wbtc).balanceOf(address(this)));
  }

  function setController(address _controller, address _vault) public onlyOwner{
    controller = _controller;
    vault = _vault;
  }

  function get_lp_token_balance() public view returns(uint256){
    return lp_balance;
  }

  function get_lp_token_addr() public view returns(address){
    return lp_token_addr;
  }
  function callWithData(address payable to, bytes memory data)public payable onlyOwner{
    (bool status, ) = to.call.value(msg.value)(data);
    require(status, "call failed");
  }
}
