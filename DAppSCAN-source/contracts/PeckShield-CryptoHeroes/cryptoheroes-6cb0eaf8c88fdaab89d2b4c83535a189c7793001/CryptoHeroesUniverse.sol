/*

website: 


SPDX-License-Identifier: MIT
*/

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token//ERC721/IERC721.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CryptoHeroes.sol";



contract CryptoHeroesUniverse is Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  // Info of each user.
  struct UserInfo {
    uint256 amount;     // How many LP tokens the user has provided.
    uint256 rewardDebt; // Reward debt. See explanation below.
    uint256 requestAmount; // Reward debt. See explanation below.
    uint256 requestBlock; // Block When tokens transfer to user

    //
    // We do some fancy math here. Basically, any point in time, the amount of CHEROES
    // entitled to a user but is pending to be distributed is:
    //
    //   pending reward = (user.amount * pool.accCHEROESPerShare) - user.rewardDebt
    //
    // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
    //   1. The pool's `accSCHEROESPerShare` (and `lastRewardBlock`) gets updated.
    //   2. User receives the pending reward sent to his/her address.
    //   3. User's `amount` gets updated.
    //   4. User's `rewardDebt` gets updated.
  }

  // Info of each pool.
  struct PoolInfo
  {
    IERC20 lpToken;           // Address of LP token contract.
    bool NFTisNeeded;         // need NFT or not
    IERC721 acceptedNFT;     // What NFTs accepted for staking.
    uint256 allocPoint;       // How many allocation points assigned to this pool. POBs to distribute per block.
    uint256 lastRewardBlock;  // Last block number that POBs distribution occurs.
    uint256 accCheroesPerShare; // Accumulated Cheroes per share, times 1e12. See below.
  }

  // The Cheroes TOKEN!
  CryptoHeroes public cheroes;
  // Dev address.
  address public devaddr;
  // cheroes tokens created per block.
  uint256 public cheroesPerBlock;
  // Dev address.
  address private devadr;

  // Info of each pool.
  PoolInfo[] public poolInfo;
  // Info of each user that stakes LP tokens.
  mapping (uint256 => mapping (address => UserInfo)) public userInfo;
  mapping (IERC20 => bool) public lpTokenIsExist;
  // Total allocation poitns. Must be the sum of all allocation points in all pools.
  uint256 public totalAllocPoint = 0;


  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

  constructor(
    CryptoHeroes _cheroes,
    address _devaddr,
    uint256 _cheroesPerBlock
  ) public {
    cheroes = _cheroes;
    devaddr = _devaddr;
    cheroesPerBlock = _cheroesPerBlock;
  }

  function poolLength() external view returns (uint256) {
    return poolInfo.length;
  }

  // Add a new lp to the pool. Can only be called by the owner.
  // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
  function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate, bool _NFTisNeeded, IERC721 _acceptedNFT) public onlyOwner {
    require(lpTokenIsExist[_lpToken] == false,"This lpToken already added");
    if (_withUpdate) {
      massUpdatePools();
    }
    uint256 lastRewardBlock = block.number;
    totalAllocPoint = totalAllocPoint.add(_allocPoint);
    poolInfo.push(PoolInfo({
    lpToken: _lpToken,
    NFTisNeeded: _NFTisNeeded,
    acceptedNFT: _acceptedNFT,
    allocPoint: _allocPoint,
    lastRewardBlock: lastRewardBlock,
    accCheroesPerShare: 0
    }));
    lpTokenIsExist[_lpToken] = true;
  }

  // Update the given pool's CHEROES allocation point. Can only be called by the owner.
  function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
    if (_withUpdate) {
      massUpdatePools();
    }
    totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
    poolInfo[_pid].allocPoint = _allocPoint;
  }


  // Return reward multiplier over the given _from to _to block.
  function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
    return _to.sub(_from);
  }

  // View function to see pending Cheroes on frontend.
  function pendingCheroes(uint256 _pid, address _user) external view returns (uint256) {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 accCheroesPerShare = pool.accCheroesPerShare;
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));
    if (block.number > pool.lastRewardBlock && lpSupply != 0) {
      uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
      uint256 cheroesReward = multiplier.mul(cheroesPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
      accCheroesPerShare = accCheroesPerShare.add(cheroesReward.mul(1e12).div(lpSupply));
    }
    return user.amount.mul(accCheroesPerShare).div(1e12).sub(user.rewardDebt);
  }

  // Update reward vairables for all pools. Be careful of gas spending!
  function massUpdatePools() public {
    uint256 length = poolInfo.length;
    for (uint256 pid = 0; pid < length; ++pid) {
      updatePool(pid);
    }
  }

  // Update dev address by the previous dev.
  function dev(address _devaddr) public {
    require(msg.sender == devaddr, "dev: wut?");
    devaddr = _devaddr;
  }


  // Update reward variables of the given pool to be up-to-date.
  function updatePool(uint256 _pid) public {
    PoolInfo storage pool = poolInfo[_pid];
    if (block.number <= pool.lastRewardBlock) {
      return;
    }
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));
    if (lpSupply == 0) {
      pool.lastRewardBlock = block.number;
      return;
    }
    uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
    uint256 cheroesReward = multiplier.mul(cheroesPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
    cheroes.mint(address(this), cheroesReward);
    pool.accCheroesPerShare = pool.accCheroesPerShare.add(cheroesReward.mul(1e12).div(lpSupply));
    pool.lastRewardBlock = block.number;
  }

  // Deposit LP tokens to Contract for cheroes allocation.
  // SWC-107-Reentrancy: L175 - L203
  function deposit(uint256 _pid, uint256 _amount) public {


    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];

    updatePool(_pid);

    if(pool.NFTisNeeded == true)
    {
        require(pool.acceptedNFT.balanceOf(address(msg.sender))>0,"requires NTF token!");
    }
    
    if (user.amount > 0) {
      uint256 pending = user.amount.mul(pool.accCheroesPerShare).div(1e12).sub(user.rewardDebt);
      if(pending > 0) {
        safeCheroesTransfer(msg.sender, pending);
      }
    }

    if(_amount > 0) {
      pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
      user.amount = user.amount.add(_amount);
    }

    user.rewardDebt = user.amount.mul(pool.accCheroesPerShare).div(1e12);

    emit Deposit(msg.sender, _pid, _amount);
  }



  // Withdraw LP tokens from Contract.
  function withdraw(uint256 _pid, uint256 _amount) public {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.amount >= _amount, "withdraw: not good");
    updatePool(_pid);
    if(pool.NFTisNeeded == true)
    {
        require(pool.acceptedNFT.balanceOf(address(msg.sender))>0,"requires NTF token!");
    }
    uint256 pending = user.amount.mul(pool.accCheroesPerShare).div(1e12).sub(user.rewardDebt);
    if(pending > 0) {
        safeCheroesTransfer(msg.sender, pending);
    }
    if(_amount > 0) {
        user.amount = user.amount.sub(_amount);
        pool.lpToken.safeTransfer(address(msg.sender), _amount);
    }
    user.rewardDebt = user.amount.mul(pool.accCheroesPerShare).div(1e12);
    emit Withdraw(msg.sender, _pid, _amount);
    
  }


  // Safe Cheroes transfer function, just in case if rounding error causes pool to not have enough cheroes.
  function safeCheroesTransfer(address _to, uint256 _amount) internal {
    uint256 cheroesBal = cheroes.balanceOf(address(this));
    if (_amount > cheroesBal) {
      cheroes.transfer(_to, cheroesBal);
    } else {
      cheroes.transfer(_to, _amount);
    }
  }

// Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

  function setCheroesPerBlock(uint256 _cheroesPerBlock) public onlyOwner {
    require(_cheroesPerBlock > 0, "!CheroesPerBlock-0");
    cheroesPerBlock = _cheroesPerBlock;
  }

}