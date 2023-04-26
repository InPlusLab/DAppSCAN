pragma solidity >=0.4.21 <0.6.0;

import "./IETHPoolBase.sol";
import "../../erc20/SafeERC20.sol";
import "../../erc20/IERC20.sol";

contract CurveInterfaceSeth{
  function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) public payable returns(uint256);
  function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_mint_amount) public returns(uint256);
}

contract SethPool is IETHPoolBase{
  using SafeERC20 for IERC20;

  CurveInterfaceSeth public pool_deposit;

  constructor() public{
    name = "Seth";
    lp_token_addr = address(0xA3D87FffcE63B53E0d54fAa1cc983B7eB0b74A9c);
    pool_deposit = CurveInterfaceSeth(0xc5424B857f758E906013F3555Dad202e4bdB4567);
  }

  function deposit_eth(uint256 _amount) internal {
    uint256[2] memory uamounts = [_amount, 0];
    pool_deposit.add_liquidity.value(_amount)(uamounts, 0);
  }


  function withdraw_from_curve(uint256 _amount) internal{
    require(_amount <= get_lp_token_balance(), "withdraw_from_curve: too large amount");
    require(address(pool_deposit).balance > 0, "money is 0");
    pool_deposit.remove_liquidity_one_coin(_amount, 0, 0);

  }

  function get_virtual_price() public view returns(uint256){
    return PriceInterfaceEth(address(pool_deposit)).get_virtual_price();
  }
}
