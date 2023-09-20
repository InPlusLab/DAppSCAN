//SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./interfaces/IVaultFarm.sol";
import "./interfaces/ISingleBond.sol";
import "./interfaces/IEpoch.sol";
import "./interfaces/IVault.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./Pool.sol";
import "./CloneFactory.sol";

contract VaultFarm is IVaultFarm, CloneFactory, OwnableUpgradeable {
  address public bond;
  address public poolImp;

  address[] public pools;
  // pool => point
  mapping(address => uint) public allocPoint;
  // asset => pool
  mapping(address => address) public assetPool;

  mapping(address => bool) public vaults;
  
  uint256 public totalAllocPoint;
  uint256 public lastUpdateSecond;
  uint256 public periodFinish;

  address[] public epoches;
  uint[] public epochRewards;

  event NewPool(address asset, address pool);
  event VaultApproved(address vault, bool approved);

  constructor() {
  }

  function initialize(address _bond, address _poolImp) external initializer {
    OwnableUpgradeable.__Ownable_init();
    bond = _bond;
    poolImp = _poolImp;
  }

  function setPoolImp(address _poolImp) external onlyOwner {
    poolImp = _poolImp;
  }

  function approveVault(address vault, bool approved)  external onlyOwner {
    vaults[vault] = approved;
    emit VaultApproved(vault, approved);
  }

  function assetPoolAlloc(address asset) external view returns (address pool, uint alloc){
    pool = assetPool[asset];
    alloc = allocPoint[pool];
  }

  function getPools() external view returns(address [] memory ps) {
    ps = pools;
  }

  function epochesRewards() external view returns(address[] memory epochs, uint[] memory rewards) {
    epochs = epoches;
    rewards = epochRewards;
  }

  function syncVault(address vault) external {
    require(vaults[vault], "invalid vault");
    address asset = IVault(vault).underlying();
    uint amount = IVault(vault).deposits(msg.sender);

    address pooladdr = assetPool[asset];
    require(pooladdr != address(0), "no asset pool");
    
    uint currAmount = Pool(pooladdr).deposits(msg.sender);
    require(amount != currAmount, "aleady migrated");

    if (amount > currAmount) {
      Pool(pooladdr).deposit(msg.sender, amount - currAmount);
    } else {
      Pool(pooladdr).withdraw(msg.sender, currAmount - amount);
    }
  }

  function syncDeposit(address _user, uint256 _amount, address asset) external override {
    require(vaults[msg.sender], "invalid vault");
    address pooladdr = assetPool[asset];
    if (pooladdr != address(0)) {
      Pool(pooladdr).deposit(_user, _amount);
    }
  }

  function syncWithdraw(address _user, uint256 _amount, address asset) external override {
    require(vaults[msg.sender], "invalid vault");
    address pooladdr = assetPool[asset];
    if (pooladdr != address(0)) {
      Pool(pooladdr).withdraw(_user, _amount);
    }
  }

  function syncLiquidate(address _user, address asset) external override {
    require(vaults[msg.sender], "invalid vault");
    address pooladdr = assetPool[asset];
    if (pooladdr != address(0)) {
      Pool(pooladdr).liquidate(_user);
    }
  }
  //SWC-100-Function Default Visibility: L111-L126
  function massUpdatePools(address[] memory epochs, uint256[] memory rewards) public {
    uint256 poolLen = pools.length;
    uint256 epochLen = epochs.length;
    

    uint[] memory epochArr = new uint[](epochLen);
    for (uint256 pi = 0; pi < poolLen; pi++) {
      for (uint256 ei = 0; ei < epochLen; ei++) {
        epochArr[ei] = rewards[ei] * allocPoint[pools[pi]] / totalAllocPoint;
      }
      Pool(pools[pi]).updateReward(epochs, epochArr, periodFinish);
    }

    epochRewards = rewards;
    lastUpdateSecond = block.timestamp;
  }

  // epochs need small for gas issue.
  function newReward(address[] memory epochs, uint256[] memory rewards, uint duration) public onlyOwner {
    require(block.timestamp >= periodFinish, 'period not finish');
    require(duration > 0, 'duration zero');

    periodFinish = block.timestamp + duration;
    epoches = epochs;
    massUpdatePools(epochs, rewards);
    
    for (uint i = 0 ; i < epochs.length; i++) {
      require(IEpoch(epochs[i]).bond() == bond, "invalid epoch");
      IERC20(epochs[i]).transferFrom(msg.sender, address(this), rewards[i]);
    }
  }

  function appendReward(address epoch, uint256 reward) public onlyOwner {
    require(block.timestamp < periodFinish, 'period not finish');
    require(IEpoch(epoch).bond() == bond, "invalid epoch");

    bool inEpoch;
    uint i;
    for (; i < epoches.length; i++) {
      if (epoch == epoches[i]) {
        inEpoch = true;
        break;
      }
    }

    uint[] memory leftRewards = calLeftAwards();
    if (!inEpoch) {
      epoches.push(epoch);
      uint[] memory newleftRewards = new uint[](epoches.length);
      for (uint j = 0; j < leftRewards.length; j++) {
        newleftRewards[j] = leftRewards[j];
      }
      newleftRewards[leftRewards.length] = reward;
      
      massUpdatePools(epoches, newleftRewards);
    } else {
      leftRewards[i] += reward;
      massUpdatePools(epoches, leftRewards);
    }

    IERC20(epoch).transferFrom(msg.sender, address(this), reward);
  }

  function removePoolEpoch(address pool, address epoch) external onlyOwner {
    Pool(pool).remove(epoch);
  }

  function calLeftAwards() internal view  returns(uint[] memory leftRewards) {
    uint len = epochRewards.length;
    leftRewards = new uint[](len);
    if (periodFinish > lastUpdateSecond && block.timestamp < periodFinish) {
      uint duration = periodFinish - lastUpdateSecond;
      uint passed = block.timestamp - lastUpdateSecond;

      for (uint i = 0 ; i < len; i++) {
        leftRewards[i] = epochRewards[i] - (passed *  epochRewards[i] / duration);
      }
    }
  }

  function newPool(uint256 _allocPoint, address asset) public onlyOwner {
    require(assetPool[asset] == address(0), "pool exist!");

    address pool = createClone(poolImp);
    Pool(pool).init();

    pools.push(pool);
    allocPoint[pool] = _allocPoint;
    assetPool[asset] = pool;
    totalAllocPoint = totalAllocPoint + _allocPoint;

    emit NewPool(asset, pool);
    uint[] memory leftRewards = calLeftAwards();
    massUpdatePools(epoches,leftRewards);
  }

  function updatePool(uint256 _allocPoint, address asset) public onlyOwner {
    address pool = assetPool[asset];
    require(pool != address(0), "pool not exist!");

    totalAllocPoint = totalAllocPoint - allocPoint[pool] + _allocPoint;
    allocPoint[pool] = _allocPoint;

    uint[] memory leftRewards = calLeftAwards();
    massUpdatePools(epoches,leftRewards);
  }

  // _pools need small for gas issue.
  function withdrawAward(address[] memory _pools, address to, bool redeem) external {
    address user = msg.sender;

    uint len = _pools.length;
    address[] memory epochs;
    uint256[] memory rewards;
    for (uint i = 0 ; i < len; i++) {
      (epochs, rewards)= Pool(_pools[i]).withdrawAward(user);
      if (redeem) {
        ISingleBond(bond).redeemOrTransfer(epochs, rewards, to);
      } else {
        ISingleBond(bond).multiTransfer(epochs, rewards, to);
      }
    }
  }

  function redeemAward(address[] memory _pools, address to) external {
    address user = msg.sender;

    uint len = _pools.length;
    address[] memory epochs;
    uint256[] memory rewards;
    for (uint i = 0 ; i < len; i++) {
      (epochs, rewards)= Pool(_pools[i]).withdrawAward(user);
      ISingleBond(bond).redeem(epochs, rewards, to);
    }
  }

  function emergencyWithdraw(address[] memory epochs, uint256[] memory amounts) external onlyOwner {
    require(epochs.length == amounts.length, "mismatch length");
    for (uint i = 0 ; i < epochs.length; i++) {
      IERC20(epochs[i]).transfer(msg.sender, amounts[i]);
    }
  }
}