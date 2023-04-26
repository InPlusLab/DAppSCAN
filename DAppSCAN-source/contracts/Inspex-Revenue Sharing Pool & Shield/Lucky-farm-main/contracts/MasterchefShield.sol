import "./libs/IMasterChef.sol";
import '@openzeppelin/contracts/access/Ownable.sol';

pragma solidity 0.8.7; //SPDX-License-Identifier: UNLICENSED

contract Shield is Ownable {
 IMasterChef public masterchef;
 
 constructor(address _owner, IMasterChef _masterchef) {
  transferOwnership(_owner);
  masterchef = _masterchef;
 }

 function add(uint256 _allocPoint, IERC20 _lpToken, uint256 _harvestIntervalInMinutes,uint256 _farmStartIntervalInMinutes) external onlyOwner {
  masterchef.add(_allocPoint, _lpToken, 0, 0);
 }

 function set(uint256 _pid, uint256 _allocPoint, uint256 _harvestIntervalInMinutes,uint256 _farmStartIntervalInMinutes) external onlyOwner {
  masterchef.set(_pid, _allocPoint, 0, 0);
 }

 function setDevAddress(address _devAddress) external onlyOwner {
  masterchef.setDevAddress(_devAddress);
 }

 function updateLuckyPerBlock(uint256 _luckyPerBlock) external onlyOwner {
  masterchef.updateLuckyPerBlock(_luckyPerBlock);
 }

}