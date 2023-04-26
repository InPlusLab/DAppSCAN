pragma solidity >=0.4.21 <0.6.0;

import "../../erc20/IERC20.sol";
import "./IWbtcPoolBase.sol";
import "../../erc20/SafeERC20.sol";

contract CurveInterfaceHbtc{
  function add_liquidity(uint256[2] memory uamounts, uint256 min_mint_amount) public;
  function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_mint_amount) public;
}

contract HbtcPool is IWbtcPoolBase{
  using SafeERC20 for IERC20;

  CurveInterfaceHbtc public pool_deposit;

  constructor() public{
    name = "Hbtc";
    lp_token_addr = address(0xb19059ebb43466C323583928285a49f558E572Fd);
    pool_deposit = CurveInterfaceHbtc(0x4CA9b3063Ec5866A4B82E437059D2C43d1be596F);
  }

  //@_amount: wbtc amount
  function deposit_wbtc(uint256 _amount) internal {
    IERC20(wbtc).approve(address(pool_deposit), 0);
    IERC20(wbtc).approve(address(pool_deposit), _amount);
    uint256[2] memory uamounts = [uint256(0), _amount];
    pool_deposit.add_liquidity(uamounts, 0);
  }


  function withdraw_from_curve(uint256 _amount) internal{
    require(_amount <= get_lp_token_balance(), "withdraw_from_curve: too large amount");
    pool_deposit.remove_liquidity_one_coin(_amount, 1, 0);
  }

  function get_virtual_price() public view returns(uint256){
    return PriceInterfaceWbtc(address(pool_deposit)).get_virtual_price();
  }
}
