pragma solidity >=0.4.21 <0.6.0;

import "../../erc20/IERC20.sol";
import "./IPoolBase.sol";
import "../../erc20/SafeERC20.sol";

contract CurveInterfaceAave{
  function add_liquidity(uint256[3] memory uamounts, uint256 min_mint_amount, bool _use_underlying) public returns(uint256);
  function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_mint_amount, bool _use_underlying) public returns(uint256);
}

contract AavePool is IUSDCPoolBase{

  using SafeERC20 for IERC20;
  CurveInterfaceAave public pool_deposit;

  constructor() public{
    name = "Aave";
    lp_token_addr = address(0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900);
    pool_deposit = CurveInterfaceAave(0xDeBF20617708857ebe4F679508E7b7863a8A8EeE);
  }

  //@_amount: USDC amount
  function deposit_usdc(uint256 _amount) internal {
    IERC20(usdc).approve(address(pool_deposit), 0);
    IERC20(usdc).approve(address(pool_deposit), _amount);
    uint256[3] memory uamounts = [uint256(0), _amount, 0];
    pool_deposit.add_liquidity(uamounts, 0, true);
  }

  function withdraw_from_curve(uint256 _amount) internal{
    require(_amount <= get_lp_token_balance(), "withdraw_from_curve: too large amount");
    IERC20(lp_token_addr).approve(address(pool_deposit), _amount);
    pool_deposit.remove_liquidity_one_coin(_amount, 1, 0, true);
  }
  function get_virtual_price() public view returns(uint256){
    return PriceInterfaceERC20(address(pool_deposit)).get_virtual_price();
  }
}
