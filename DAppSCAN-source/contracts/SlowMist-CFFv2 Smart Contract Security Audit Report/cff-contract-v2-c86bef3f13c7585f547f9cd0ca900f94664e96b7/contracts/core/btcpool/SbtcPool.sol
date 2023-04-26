pragma solidity >=0.4.21 <0.6.0;

import "../../erc20/IERC20.sol";
import "./IWbtcPoolBase.sol";
import "../../erc20/SafeERC20.sol";

contract CurveInterfaceSbtc{
  function add_liquidity(uint256[3] memory uamounts, uint256 min_mint_amount) public;
  function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_mint_amount) public;
  function get_virtual_price() public view returns(uint256);
}

contract SbtcPool is IWbtcPoolBase{
  using SafeERC20 for IERC20;

  CurveInterfaceSbtc public pool_deposit;

  constructor() public{
    name = "Sbtc";
    lp_token_addr = address(0x075b1bb99792c9E1041bA13afEf80C91a1e70fB3);
    pool_deposit = CurveInterfaceSbtc(0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714);
  }

  //@_amount: wbtc amount
  function deposit_wbtc(uint256 _amount) internal {
    IERC20(wbtc).approve(address(pool_deposit), 0);
    IERC20(wbtc).approve(address(pool_deposit), _amount);
    uint256[3] memory uamounts = [uint256(0), _amount, uint256(0)];
    pool_deposit.add_liquidity(uamounts, 0);
  }


  function withdraw_from_curve(uint256 _amount) internal{
    require(_amount <= get_lp_token_balance(), "withdraw_from_curve: too large amount");
    pool_deposit.remove_liquidity_one_coin(_amount, 1, 0);
  }

  function get_virtual_price() public view returns(uint256){
    return pool_deposit.get_virtual_price();
  }
}
