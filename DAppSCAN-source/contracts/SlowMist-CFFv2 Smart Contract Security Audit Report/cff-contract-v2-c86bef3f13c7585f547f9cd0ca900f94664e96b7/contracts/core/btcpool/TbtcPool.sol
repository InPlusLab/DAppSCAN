pragma solidity >=0.4.21 <0.6.0;

import "../../erc20/IERC20.sol";
import "./IWbtcPoolBase.sol";
import "../../erc20/SafeERC20.sol";

contract CurveInterfaceTbtc{
  function add_liquidity(uint256[4] memory uamounts, uint256 min_mint_amount) public returns(uint256);
  function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_mint_amount) public returns(uint256);

  address public pool;
}

contract TbtcPool is IWbtcPoolBase{
  using SafeERC20 for IERC20;

  CurveInterfaceTbtc public pool_deposit;

  constructor() public{
    name = "Tbtc";
    lp_token_addr = address(0x64eda51d3Ad40D56b9dFc5554E06F94e1Dd786Fd);
    pool_deposit = CurveInterfaceTbtc(0xaa82ca713D94bBA7A89CEAB55314F9EfFEdDc78c);
  }

  //@_amount: wbtc amount
  function deposit_wbtc(uint256 _amount) internal {
    IERC20(wbtc).approve(address(pool_deposit), 0);
    IERC20(wbtc).approve(address(pool_deposit), _amount);
    uint256[4] memory uamounts = [uint256(0), 0, _amount, 0];
    pool_deposit.add_liquidity(uamounts, 0);
  }


  function withdraw_from_curve(uint256 _amount) internal{
    require(_amount <= get_lp_token_balance(), "withdraw_from_curve: too large amount");
    IERC20(lp_token_addr).approve(address(pool_deposit), 0);
    IERC20(lp_token_addr).approve(address(pool_deposit), _amount);
    pool_deposit.remove_liquidity_one_coin(_amount, 2, 0);
  }

  function get_virtual_price() public view returns(uint256){
    return PriceInterfaceWbtc(pool_deposit.pool()).get_virtual_price();
  }
}
