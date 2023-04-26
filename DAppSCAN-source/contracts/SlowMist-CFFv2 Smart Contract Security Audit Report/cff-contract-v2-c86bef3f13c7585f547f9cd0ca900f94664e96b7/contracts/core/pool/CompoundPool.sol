pragma solidity >=0.4.21 <0.6.0;

import "../../erc20/IERC20.sol";
import "./IPoolBase.sol";
import "../../erc20/SafeERC20.sol";

contract CurveInterfaceCompound{
  function add_liquidity(uint256[2] memory uamounts, uint256 min_mint_amount) public;
  //function remove_liquidity(uint256 _amount, uint256[2] memory min_uamounts) public;
  function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_mint_amount) public;

  address public curve;
}

contract CompoundPool is IUSDCPoolBase{
  using SafeERC20 for IERC20;

  CurveInterfaceCompound public pool_deposit;

  constructor() public{
    name = "Compound";
    lp_token_addr = address(0x845838DF265Dcd2c412A1Dc9e959c7d08537f8a2);
    pool_deposit = CurveInterfaceCompound(0xeB21209ae4C2c9FF2a86ACA31E123764A3B6Bc06);
  }

  //@_amount: USDC amount
  function deposit_usdc(uint256 _amount) internal {
    IERC20(usdc).approve(address(pool_deposit), 0);
    IERC20(usdc).approve(address(pool_deposit), _amount);
    uint256[2] memory uamounts = [uint256(0), _amount];
    pool_deposit.add_liquidity(uamounts, 0);
  }

  function withdraw_from_curve(uint256 _amount) internal{
    require(_amount <= get_lp_token_balance(), "withdraw_from_curve: too large amount");
    IERC20(lp_token_addr).approve(address(pool_deposit), _amount);
    pool_deposit.remove_liquidity_one_coin(_amount, 1, 0);
  }

  function get_virtual_price() public view returns(uint256){
    return PriceInterfaceERC20(pool_deposit.curve()).get_virtual_price();
  }
}
