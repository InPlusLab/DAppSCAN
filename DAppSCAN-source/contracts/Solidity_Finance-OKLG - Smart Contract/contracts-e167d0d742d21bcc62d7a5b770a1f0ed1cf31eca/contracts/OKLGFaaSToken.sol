// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '@openzeppelin/contracts/interfaces/IERC721.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

/**
 * @title OKLGFaaSToken (sOKLG)
 * @notice Represents a contract where a token owner has put her tokens up for others to stake and earn said tokens.
 */
contract OKLGFaaSToken is ERC20 {
  using SafeMath for uint256;
  bool public contractIsRemoved = false;

  IERC20 private _rewardsToken;
  IERC20 private _stakedERC20;
  IERC721 private _stakedERC721;
  PoolInfo public pool;
  address private constant _burner = 0x000000000000000000000000000000000000dEaD;

  struct PoolInfo {
    address creator; // address of contract creator
    address tokenOwner; // address of original rewards token owner
    uint256 origTotSupply; // supply of rewards tokens put up to be rewarded by original owner
    uint256 curRewardsSupply; // current supply of rewards
    uint256 totalTokensStaked; // current amount of tokens staked
    uint256 creationBlock; // block this contract was created
    uint256 perBlockNum; // amount of rewards tokens rewarded per block
    uint256 lockedUntilDate; // unix timestamp of how long this contract is locked and can't be changed
    // uint256 allocPoint; // How many allocation points assigned to this pool. ERC20s to distribute per block.
    uint256 lastRewardBlock; // Last block number that ERC20s distribution occurs.
    uint256 accERC20PerShare; // Accumulated ERC20s per share, times 1e36.
    uint256 stakeTimeLockSec; // number of seconds after depositing the user is required to stake before unstaking
    bool isStakedNft;
  }

  struct StakerInfo {
    uint256 amountStaked;
    uint256 blockOriginallyStaked; // block the user originally staked
    uint256 timeOriginallyStaked; // unix timestamp in seconds that the user originally staked
    uint256 blockLastHarvested; // the block the user last claimed/harvested rewards
    uint256 rewardDebt; // Reward debt. See explanation below.
    uint256[] nftTokenIds; // if this is an NFT staking pool, make sure we store the token IDs here
  }

  struct BlockTokenTotal {
    uint256 blockNumber;
    uint256 totalTokens;
  }

  // mapping of userAddresses => tokenAddresses that can
  // can be evaluated to determine for a particular user which tokens
  // they are staking.
  mapping(address => StakerInfo) public stakers;

  event Deposit(address indexed user, uint256 amount);
  event Withdraw(address indexed user, uint256 amount);

  /**
   * @notice The constructor for the Staking Token.
   * @param _name Name of the staking token
   * @param _symbol Name of the staking token symbol
   * @param _rewardSupply The amount of tokens to mint on construction, this should be the same as the tokens provided by the creating user.
   * @param _rewardsTokenAddy Contract address of token to be rewarded to users
   * @param _stakedTokenAddy Contract address of token to be staked by users
   * @param _originalTokenOwner Address of user putting up staking tokens to be staked
   * @param _perBlockAmount Amount of tokens to be rewarded per block
   * @param _lockedUntilDate Unix timestamp that the staked tokens will be locked. 0 means locked forever until all tokens are staked
   * @param _stakeTimeLockSec number of seconds a user is required to stake, or 0 if none
   * @param _isStakedNft is this an NFT staking pool
   */
  constructor(
    string memory _name,
    string memory _symbol,
    uint256 _rewardSupply,
    address _rewardsTokenAddy,
    address _stakedTokenAddy,
    address _originalTokenOwner,
    uint256 _perBlockAmount,
    uint256 _lockedUntilDate,
    uint256 _stakeTimeLockSec,
    bool _isStakedNft
  ) ERC20(_name, _symbol) {
    require(
      _perBlockAmount > uint256(0) && _perBlockAmount <= uint256(_rewardSupply),
      'per block amount must be more than 0 and less than supply'
    );

    // A locked date of '0' corresponds to being locked forever until the supply has expired and been rewards to all stakers
    require(
      _lockedUntilDate > block.timestamp || _lockedUntilDate == 0,
      'locked time must be after now or 0'
    );

    _rewardsToken = IERC20(_rewardsTokenAddy);
    if (_isStakedNft) {
      _stakedERC721 = IERC721(_stakedTokenAddy);
    } else {
      _stakedERC20 = IERC20(_stakedTokenAddy);
    }

    pool = PoolInfo({
      creator: msg.sender,
      tokenOwner: _originalTokenOwner,
      origTotSupply: _rewardSupply,
      curRewardsSupply: _rewardSupply,
      totalTokensStaked: 0,
      creationBlock: 0,
      perBlockNum: _perBlockAmount,
      lockedUntilDate: _lockedUntilDate,
      lastRewardBlock: block.number,
      accERC20PerShare: 0,
      stakeTimeLockSec: _stakeTimeLockSec,
      isStakedNft: _isStakedNft
    });
  }

  // SHOULD ONLY BE CALLED AT CONTRACT CREATION and allows changing
  // the initial supply if tokenomics of token transfer causes
  // the original staking contract supply to be less than the original
  function updateSupply(uint256 _newSupply) external {
    require(
      msg.sender == pool.creator,
      'only contract creator can update the supply'
    );
    pool.origTotSupply = _newSupply;
    pool.curRewardsSupply = _newSupply;
  }

  function stakedTokenAddress() external view returns (address) {
    return pool.isStakedNft ? address(_stakedERC721) : address(_stakedERC20);
  }

  function rewardsTokenAddress() external view returns (address) {
    return address(_rewardsToken);
  }

  function tokenOwner() external view returns (address) {
    return pool.tokenOwner;
  }

  function getLockedUntilDate() external view returns (uint256) {
    return pool.lockedUntilDate;
  }

  function removeStakeableTokens() external {
    require(
      msg.sender == pool.creator || msg.sender == pool.tokenOwner,
      'caller must be the contract creator or owner to remove stakable tokens'
    );
    _rewardsToken.transfer(pool.tokenOwner, pool.curRewardsSupply);
    pool.curRewardsSupply = 0;
    contractIsRemoved = true;
  }

  // function updateTimestamp(uint256 _newTime) external {
  //   require(
  //     msg.sender == tokenOwner,
  //     'updateTimestamp user must be original token owner'
  //   );
  //   require(
  //     _newTime > lockedUntilDate || _newTime == 0,
  //     'you cannot change timestamp if it is before the locked time or was set to be locked forever'
  //   );
  //   lockedUntilDate = _newTime;
  // }

  function stakeTokens(uint256 _amount, uint256[] memory _tokenIds) public {
    require(
      getLastStakableBlock() > block.number,
      'this farm is expired and no more stakers can be added'
    );

    _updatePool();

    if (balanceOf(msg.sender) > 0) {
      _harvestTokens(msg.sender);
    }

    uint256 _finalAmountTransferred;
    if (pool.isStakedNft) {
      require(
        _tokenIds.length > 0,
        "you need to provide NFT token IDs you're staking"
      );
      for (uint256 _i = 0; _i < _tokenIds.length; _i++) {
        _stakedERC721.transferFrom(msg.sender, address(this), _tokenIds[_i]);
      }

      _finalAmountTransferred = _tokenIds.length;
    } else {
      uint256 _contractBalanceBefore = _stakedERC20.balanceOf(address(this));
      _stakedERC20.transferFrom(msg.sender, address(this), _amount);

      // in the event a token contract on transfer taxes, burns, etc. tokens
      // the contract might not get the entire amount that the user originally
      // transferred. Need to calculate from the previous contract balance
      // so we know how many were actually transferred.
      _finalAmountTransferred = _stakedERC20.balanceOf(address(this)).sub(
        _contractBalanceBefore
      );
    }

    if (totalSupply() == 0) {
      pool.creationBlock = block.number;
      pool.lastRewardBlock = block.number;
    }
    _mint(msg.sender, _finalAmountTransferred);
    StakerInfo storage _staker = stakers[msg.sender];
    _staker.amountStaked = _staker.amountStaked.add(_finalAmountTransferred);
    _staker.blockOriginallyStaked = block.number;
    _staker.timeOriginallyStaked = block.timestamp;
    _staker.blockLastHarvested = block.number;
    _staker.rewardDebt = _staker.amountStaked.mul(pool.accERC20PerShare).div(
      1e36
    );
    for (uint256 _i = 0; _i < _tokenIds.length; _i++) {
      _staker.nftTokenIds.push(_tokenIds[_i]);
    }
    _updNumStaked(_finalAmountTransferred, 'add');
    emit Deposit(msg.sender, _finalAmountTransferred);
  }

  // pass 'false' for _shouldHarvest for emergency unstaking without claiming rewards
  function unstakeTokens(uint256 _amount, bool _shouldHarvest) external {
    StakerInfo memory _staker = stakers[msg.sender];
    uint256 _userBalance = _staker.amountStaked;
    require(
      pool.isStakedNft ? true : _amount <= _userBalance,
      'user can only unstake amount they have currently staked or less'
    );

    // allow unstaking if the user is emergency unstaking and not getting rewards or
    // if theres a time lock that it's past the time lock or
    // the contract rewards were removed by the original contract creator or
    // the contract is expired
    require(
      !_shouldHarvest ||
        block.timestamp >=
        _staker.timeOriginallyStaked.add(pool.stakeTimeLockSec) ||
        contractIsRemoved ||
        block.number > getLastStakableBlock(),
      'you have not staked for minimum time lock yet and the pool is not expired'
    );

    _updatePool();

    if (_shouldHarvest) {
      _harvestTokens(msg.sender);
    }

    uint256 _amountToRemoveFromStaked = pool.isStakedNft
      ? _userBalance
      : _amount;
    transfer(
      _burner,
      _amountToRemoveFromStaked > balanceOf(msg.sender)
        ? balanceOf(msg.sender)
        : _amountToRemoveFromStaked
    );
    if (pool.isStakedNft) {
      for (uint256 _i = 0; _i < _staker.nftTokenIds.length; _i++) {
        _stakedERC721.transferFrom(
          address(this),
          msg.sender,
          _staker.nftTokenIds[_i]
        );
      }
    } else {
      require(
        _stakedERC20.transfer(msg.sender, _amountToRemoveFromStaked),
        'unable to send user original tokens'
      );
    }

    if (balanceOf(msg.sender) <= 0) {
      delete stakers[msg.sender];
    } else {
      _staker.amountStaked = _staker.amountStaked.sub(
        _amountToRemoveFromStaked
      );
    }
    _updNumStaked(_amountToRemoveFromStaked, 'remove');
    emit Withdraw(msg.sender, _amountToRemoveFromStaked);
  }

  function emergencyUnstake() external {
    StakerInfo memory _staker = stakers[msg.sender];
    uint256 _amountToRemoveFromStaked = _staker.amountStaked;
    require(
      _amountToRemoveFromStaked > 0,
      'user can only unstake if they have tokens in the pool'
    );

    transfer(
      _burner,
      _amountToRemoveFromStaked > balanceOf(msg.sender)
        ? balanceOf(msg.sender)
        : _amountToRemoveFromStaked
    );
    if (pool.isStakedNft) {
      for (uint256 _i = 0; _i < _staker.nftTokenIds.length; _i++) {
        _stakedERC721.transferFrom(
          address(this),
          msg.sender,
          _staker.nftTokenIds[_i]
        );
      }
    } else {
      require(
        _stakedERC20.transfer(msg.sender, _amountToRemoveFromStaked),
        'unable to send user original tokens'
      );
    }

    delete stakers[msg.sender];
    _updNumStaked(_amountToRemoveFromStaked, 'remove');
    emit Withdraw(msg.sender, _amountToRemoveFromStaked);
  }

  function harvestForUser(address _userAddy, bool _autoCompound)
    external
    returns (uint256)
  {
    require(
      msg.sender == pool.creator || msg.sender == _userAddy,
      'can only harvest tokens for someone else if this was the contract creator'
    );
    _updatePool();
    uint256 _tokensToUser = _harvestTokens(_userAddy);

    if (
      _autoCompound &&
      !pool.isStakedNft &&
      address(_rewardsToken) == address(_stakedERC20)
    ) {
      uint256[] memory _placeholder;
      stakeTokens(_tokensToUser, _placeholder);
    }

    return _tokensToUser;
  }

  function getLastStakableBlock() public view returns (uint256) {
    uint256 _blockToAdd = pool.creationBlock == 0
      ? block.number
      : pool.creationBlock;
    return pool.origTotSupply.div(pool.perBlockNum).add(_blockToAdd);
  }

  function calcHarvestTot(address _userAddy) public view returns (uint256) {
    StakerInfo memory _staker = stakers[_userAddy];

    if (
      _staker.blockLastHarvested >= block.number ||
      _staker.blockOriginallyStaked == 0 ||
      pool.totalTokensStaked == 0
    ) {
      return uint256(0);
    }

    uint256 _accERC20PerShare = pool.accERC20PerShare;

    if (block.number > pool.lastRewardBlock && pool.totalTokensStaked != 0) {
      uint256 _endBlock = getLastStakableBlock();
      uint256 _lastBlock = block.number < _endBlock ? block.number : _endBlock;
      uint256 _nrOfBlocks = _lastBlock.sub(pool.lastRewardBlock);
      uint256 _erc20Reward = _nrOfBlocks.mul(pool.perBlockNum);
      _accERC20PerShare = _accERC20PerShare.add(
        _erc20Reward.mul(1e36).div(pool.totalTokensStaked)
      );
    }

    return
      _staker.amountStaked.mul(_accERC20PerShare).div(1e36).sub(
        _staker.rewardDebt
      );
  }

  // Update reward variables of the given pool to be up-to-date.
  function _updatePool() private {
    uint256 _endBlock = getLastStakableBlock();
    uint256 _lastBlock = block.number < _endBlock ? block.number : _endBlock;

    if (_lastBlock <= pool.lastRewardBlock) {
      return;
    }
    uint256 _stakedSupply = pool.totalTokensStaked;
    if (_stakedSupply == 0) {
      pool.lastRewardBlock = _lastBlock;
      return;
    }

    uint256 _nrOfBlocks = _lastBlock.sub(pool.lastRewardBlock);
    uint256 _erc20Reward = _nrOfBlocks.mul(pool.perBlockNum);

    pool.accERC20PerShare = pool.accERC20PerShare.add(
      _erc20Reward.mul(1e36).div(_stakedSupply)
    );
    pool.lastRewardBlock = _lastBlock;
  }

  function _harvestTokens(address _userAddy) private returns (uint256) {
    StakerInfo storage _staker = stakers[_userAddy];
    require(_staker.blockOriginallyStaked > 0, 'user must have tokens staked');

    uint256 _num2Trans = calcHarvestTot(_userAddy);
    if (_num2Trans > 0) {
      require(
        _rewardsToken.transfer(_userAddy, _num2Trans),
        'unable to send user their harvested tokens'
      );
      pool.curRewardsSupply = pool.curRewardsSupply.sub(_num2Trans);
    }
    _staker.rewardDebt = _staker.amountStaked.mul(pool.accERC20PerShare).div(
      1e36
    );
    _staker.blockLastHarvested = block.number;
    return _num2Trans;
  }

  // update the amount currently staked after a user harvests
  function _updNumStaked(uint256 _amount, string memory _operation) private {
    if (_compareStr(_operation, 'remove')) {
      pool.totalTokensStaked = pool.totalTokensStaked.sub(_amount);
    } else {
      pool.totalTokensStaked = pool.totalTokensStaked.add(_amount);
    }
  }

  function _compareStr(string memory a, string memory b)
    private
    pure
    returns (bool)
  {
    return (keccak256(abi.encodePacked((a))) ==
      keccak256(abi.encodePacked((b))));
  }
}
