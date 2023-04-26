pragma solidity >=0.4.21 <0.6.0;
import "../utils/Ownable.sol";

contract PMBParams is Ownable{
  uint256 public ratio_base;
  uint256 public withdraw_fee_ratio;

  uint256 public mortgage_ratio;
  uint256 public liquidate_fee_ratio;
  uint256 public minimum_deposit_amount;

  address payable public plut_fee_pool;

  constructor() public{
    ratio_base = 1000000;
    minimum_deposit_amount = 0;
  }

  function changeWithdrawFeeRatio(uint256 _ratio) public onlyOwner{
    require(_ratio < ratio_base, "too large");
    withdraw_fee_ratio = _ratio;
  }

  function changeMortgageRatio(uint256 _ratio) public onlyOwner{
    require(_ratio > ratio_base, "too small");
    mortgage_ratio = _ratio;
  }

  function changeLiquidateFeeRatio(uint256 _ratio) public onlyOwner{
    require(_ratio < ratio_base, "too large");
    liquidate_fee_ratio = _ratio;
  }
  function changeMinimumDepositAmount(uint256 _amount) public onlyOwner{
    minimum_deposit_amount = _amount;
  }
  function changePlutFeePool(address payable _pool) public onlyOwner{
    plut_fee_pool = _pool;
  }
}
