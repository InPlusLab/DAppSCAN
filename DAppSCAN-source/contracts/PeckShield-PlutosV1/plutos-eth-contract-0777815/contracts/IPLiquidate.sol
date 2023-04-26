pragma solidity >=0.4.21 <0.6.0;

contract IPLiquidate{
  function liquidate_asset(address payable _sender, uint256 _target_amount, uint256 _stable_amount) public ;
}
