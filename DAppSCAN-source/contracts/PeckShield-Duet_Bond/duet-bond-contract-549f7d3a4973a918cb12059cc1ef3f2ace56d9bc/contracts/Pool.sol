pragma solidity 0.8.11;

import "./interfaces/ISingleBond.sol";
import "./interfaces/IEpoch.sol";
import "./interfaces/IVaultFarm.sol";

contract Pool {
  uint256 public constant SCALE = 1e12;
  address public farming;

  address[] public epoches;
  mapping(address => bool) public validEpoches;

  mapping(address => uint) public deposits;
  // user => epoch => debt
  mapping(address => mapping(address => uint)) public rewardDebt;
  mapping(address => mapping(address => uint)) public rewardAvailable;

  struct EpochInfo {
    uint accPerShare;       //Accumulated rewards per share, times SCALE
    uint epochPerSecond;   // for total deposit 
  }


  mapping(address => EpochInfo) public epochInfos;

  uint256 public totalAmount;
  uint256 public lastRewardSecond;
  uint256 public periodEnd;

  event Deposit(address indexed user, uint256 amount);
  event Withdraw(address indexed user, uint256 amount);

  constructor() {
  }

  modifier onlyFarming() {
    require(farming == msg.sender, "must call from framing");
    _;
  }

  function getEpoches() external view returns(address[] memory){
    return epoches;
  }

  function addEpoch(address epoch) internal {
    if(!validEpoches[epoch]) {
      validEpoches[epoch] = true;
      epoches.push(epoch);
    }
  }

  // remove some item for saving gas (array issue).
  // should only used when no such epoch assets.
  function remove(address epoch) external onlyFarming {
      require(validEpoches[epoch], "Not a valid epoch");
      validEpoches[epoch] = false;

      uint len = epoches.length;
      for (uint i = 0; i < len; i++) {
        if( epoch == epoches[i]) {
            if (i == len - 1) {
                epoches.pop();
                break;
            } else {
              epoches[i] = epoches[len - 1];
              epoches.pop();
              break;
            }
        }
      }
  }

  function init() external {
    require(address(farming) == address(0), "inited");
    farming = msg.sender;
  }

  function updateReward(address[] memory epochs, uint[] memory awards, uint periodFinish) public onlyFarming {
      if(periodFinish <= block.timestamp) {
        return ;
      }

      require(epochs.length == awards.length, "mismatch length");
      updatePool();

      periodEnd = periodFinish;
      uint duration = periodFinish - block.timestamp;
      
      for(uint256 i = 0; i< epochs.length; i++) { 
        addEpoch(epochs[i]);
        EpochInfo storage epinfo =  epochInfos[epochs[i]];
        epinfo.epochPerSecond = awards[i] / duration;
      }
  }

  function getPassed() internal view returns (uint) {
    uint endTs;
    if (periodEnd > block.timestamp) {
      endTs = block.timestamp;
    } else {
      endTs = periodEnd;
    }
    
    if (endTs <= lastRewardSecond) {
      return 0;
    }

    return endTs - lastRewardSecond;
  }

  function updatePool() internal {
    uint passed = getPassed();

    if (totalAmount > 0 && passed > 0) {
      for(uint256 i = 0; i< epoches.length; i++) { 
        EpochInfo storage epinfo = epochInfos[epoches[i]];
        epinfo.accPerShare += epinfo.epochPerSecond * passed * SCALE / totalAmount;
      }
    }
    lastRewardSecond = block.timestamp;
    
  }

  function updateUser(address user, uint newDeposit, bool liq) internal {
    
    for(uint256 i = 0; i< epoches.length; i++) { 
      EpochInfo memory epinfo =  epochInfos[epoches[i]];
      if (liq) {
        rewardAvailable[user][epoches[i]] = 0;
      } else {
        rewardAvailable[user][epoches[i]] += (deposits[user] * epinfo.accPerShare / SCALE) - rewardDebt[user][epoches[i]];
      }
      
      rewardDebt[user][epoches[i]] = newDeposit * epinfo.accPerShare / SCALE;
    }  
  }

  function deposit(address user, uint256 amount) external onlyFarming {
    updatePool();
    uint newDeposit = deposits[user] + amount;

    updateUser(user, newDeposit, false);
    deposits[user] = newDeposit;
    totalAmount += amount;

    emit Deposit(user, amount);
  }

  function withdraw(address user, uint256 amount) external onlyFarming {
    updatePool();
    
    uint newDeposit = deposits[user] - amount;
    updateUser(user, newDeposit, false);

    deposits[user] = newDeposit;
    totalAmount -= amount;
    emit Withdraw(user, amount);
  }

  function liquidate(address user) external onlyFarming {
    updatePool();

    updateUser(user,0, true);
    uint amount = deposits[user];
    totalAmount -= amount;
    deposits[user] = 0;
    emit Withdraw(user, amount);
  }

  function pending(address user) public view returns (address[] memory epochs, uint256[] memory rewards) {
    uint passed = getPassed();

    uint len = epoches.length;
    rewards = new uint[](len);
    
    for(uint256 i = 0; i< epoches.length; i++) {

      EpochInfo memory epinfo =  epochInfos[epoches[i]];
      uint currPending = 0;
      if (passed > 0) {
        currPending = epinfo.epochPerSecond * passed * deposits[user] / totalAmount;
      }
      rewards[i] = rewardAvailable[user][epoches[i]] 
        + currPending
        + (deposits[user] * epinfo.accPerShare / SCALE) - rewardDebt[user][epoches[i]];
    }

    epochs = epoches;
  }

  function withdrawAward(address user) external returns (address[] memory epochs, uint256[] memory rewards) {
    require(farming == msg.sender, "must call from framing");
    updatePool();
    updateUser(user, deposits[user], false);

    (epochs, rewards) = pending(user);

    for(uint256 i = 0; i< epoches.length; i++) {
      rewardAvailable[user][epoches[i]] = 0;
    }
  }
}