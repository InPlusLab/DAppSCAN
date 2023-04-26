pragma solidity >=0.4.21 <0.6.0;

contract ConvexRewardInterface{
function getReward(address, bool) external returns(bool);
function withdraw(uint256, bool) external returns(bool);
}

contract ConvexBoosterInterface{
  function poolInfo(uint256) external view returns(address,address,address,address,address,bool);
  function poolLength() external view returns (uint256);
  function depositAll(uint256 _pid, bool _stake) external returns(bool);
  function withdraw(uint256 _pid, uint256 _amount) public returns(bool);
}
