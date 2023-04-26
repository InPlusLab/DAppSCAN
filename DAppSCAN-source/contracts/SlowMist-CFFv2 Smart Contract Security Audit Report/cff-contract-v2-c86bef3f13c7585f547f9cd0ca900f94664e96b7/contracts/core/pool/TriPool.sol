pragma solidity >=0.4.21 <0.6.0;

import "../../erc20/IERC20.sol";
import "./IPoolBase.sol";
import "../../erc20/SafeERC20.sol";

contract CurveInterfaceTri{
  function add_liquidity(uint256[3] memory uamounts, uint256 min_mint_amount) public;
  //function remove_liquidity(uint256 _amount, uint256[3] memory min_uamounts) public;
  function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_mint_amount) public;
}

contract TriPool is IUSDCPoolBase{
  using SafeERC20 for IERC20;

  CurveInterfaceTri public pool_deposit;

  constructor() public{
    name = "3Pool";
    lp_token_addr = address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    pool_deposit = CurveInterfaceTri(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
  }

  //@_amount: USDC amount
  function deposit_usdc(uint256 _amount) internal {
    IERC20(usdc).approve(address(pool_deposit), 0);
    IERC20(usdc).approve(address(pool_deposit), _amount);
    uint256[3] memory uamounts = [uint256(0), _amount, 0];
    pool_deposit.add_liquidity(uamounts, 0);
  }


  function withdraw_from_curve(uint256 _amount) internal{
    require(_amount <= get_lp_token_balance(), "withdraw_from_curve: too large amount");
    pool_deposit.remove_liquidity_one_coin(_amount, 1, 0);
  }

  function get_virtual_price() public view returns(uint256){
    return PriceInterfaceERC20(address(pool_deposit)).get_virtual_price();
  }
}
