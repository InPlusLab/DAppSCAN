pragma solidity >=0.4.21 <0.6.0;
import "../../utils/Ownable.sol";
import "../IPool.sol";
import "../../erc20/SafeERC20.sol";
import "../../erc20/IERC20.sol";

contract PriceInterfaceEth{
  function get_virtual_price() public view returns(uint256);
}

contract IETHPoolBase is ICurvePool, Ownable{
  using SafeERC20 for IERC20;

  address public controller;
  address public vault;
  address public lp_token_addr;

  uint256 public lp_balance;
  uint256 public deposit_eth_amount;
  uint256 public withdraw_eth_amount;

  modifier onlyController(){
    require((controller == msg.sender)||(vault == msg.sender), "only controller can call this");
    _;
  }

  constructor() public{}

  function deposit_eth(uint256 amount) internal;

  function deposit(uint256 amount) public onlyController{
    require(amount <= address(this).balance, "IETHPoolBase, not enough amount");
    uint _amount = amount;
    deposit_eth_amount = deposit_eth_amount + _amount;
    deposit_eth(_amount);
    uint256 cur = IERC20(lp_token_addr).balanceOf(address(this));
    lp_balance = lp_balance + cur;
    IERC20(lp_token_addr).safeTransfer(msg.sender, cur);
  }

  function withdraw_from_curve(uint256 _amount) internal;

  //@_amount: lp token amount
  function withdraw(uint256 _amount) public onlyController{
      withdraw_from_curve(_amount);
      lp_balance = lp_balance - _amount;

      (bool status, ) = msg.sender.call.value(address(this).balance)("");
      require(status, "IETHPoolBase transfer eth failed");
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

  function() external payable{}
  function callWithData(address payable to, bytes memory data)public payable onlyOwner{
    (bool status, ) = to.call.value(msg.value)(data);
    require(status, "call failed");
  }
}
