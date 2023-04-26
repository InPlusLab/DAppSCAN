pragma solidity >=0.4.21 <0.6.0;

contract IPMBParams{
  uint256 public ratio_base;
  uint256 public withdraw_fee_ratio;

  uint256 public mortgage_ratio;
  uint256 public liquidate_fee_ratio;
  uint256 public minimum_deposit_amount;

  address payable public plut_fee_pool;
}
