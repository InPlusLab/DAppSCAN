pragma solidity >=0.4.21 <0.6.0;

import "../../utils/Ownable.sol";
import "../IPool.sol";
import "../../utils/TokenClaimer.sol";
import "../../erc20/IERC20.sol";
import "./IPoolBase.sol";

contract CurveInterfaceLusd{
  function add_liquidity(address _pool, uint256[4] memory _deposit_amounts, uint256 _min_mint_amount) public returns(uint256);
  function remove_liquidity_one_coin(address _pool, uint256 _burn_amount, int128 i, uint256 _min_amount) public returns(uint256);
}

contract CRVGaugeInterfaceERC20_lusd{
  function deposit(uint256 _value) public;
  function withdraw(uint256 _value) public;
  function claim_rewards(address _address) public;
}


contract LusdPool is IUSDCPoolBase{
  CurveInterfaceLusd public pool_deposit;
  address public meta_pool_addr;


  constructor() public{
    name = "Lusd";

    pool_deposit = CurveInterfaceLusd(0xA79828DF1850E8a3A3064576f380D90aECDD3359);
    meta_pool_addr = address(0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA);
    lp_token_addr = address(0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA);
  }

  //@_amount: USDC amount
  function deposit_usdc(uint256 _amount) internal {
    IERC20(usdc).approve(address(pool_deposit), 0);
    IERC20(usdc).approve(address(pool_deposit), _amount);
    uint256[4] memory uamounts = [0,0, _amount, 0];
    pool_deposit.add_liquidity(
        meta_pool_addr,
        uamounts,
        0
    );
  }


  function withdraw_from_curve(uint256 _amount) internal {
    require(_amount <= get_lp_token_balance(), "withdraw_from_curve: too large amount");
    IERC20(lp_token_addr).approve(address(pool_deposit), _amount);
    pool_deposit.remove_liquidity_one_coin(
        meta_pool_addr,
        _amount,
        2,
        0
    );
  }

  function get_virtual_price() public view returns(uint256) {
    return PriceInterfaceERC20(address(meta_pool_addr)).get_virtual_price();
  }
}
