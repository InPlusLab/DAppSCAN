pragma solidity 0.6.12;

import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC1155/ERC1155.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC20/IERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/token/ERC20/SafeERC20.sol';
import 'OpenZeppelin/openzeppelin-contracts@3.2.0/contracts/utils/ReentrancyGuard.sol';

import '../utils/HomoraMath.sol';
import '../../interfaces/IERC20Wrapper.sol';
import '../../interfaces/IStakingRewards.sol';

contract WStakingRewards is ERC1155('WStakingRewards'), ReentrancyGuard, IERC20Wrapper {
  using SafeMath for uint;
  using HomoraMath for uint;
  using SafeERC20 for IERC20;

  address public immutable staking; // Staking reward contract address
  address public immutable underlying; // Underlying token address
  address public immutable reward; // Reward token address

  constructor(
    address _staking,
    address _underlying,
    address _reward
  ) public {
    staking = _staking;
    underlying = _underlying;
    reward = _reward;
    IERC20(_underlying).approve(_staking, uint(-1));
  }
//SWC-104-Unchecked Call Return Value:L29
  /// @dev Return the underlying ERC20 for the given ERC1155 token id.
  function getUnderlyingToken(uint) external view override returns (address) {
    return underlying;
  }

  /// @dev Return the conversion rate from ERC1155 to ERC20, multiplied 2**112.
  function getUnderlyingRate(uint) external view override returns (uint) {
    return 2**112;
  }

  /// @dev Mint ERC1155 token for the specified amount
  /// @param amount Token amount to wrap
  function mint(uint amount) external nonReentrant returns (uint) {
    IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
    IStakingRewards(staking).stake(amount);
    uint rewardPerToken = IStakingRewards(staking).rewardPerToken();
    _mint(msg.sender, rewardPerToken, amount, '');
    return rewardPerToken;
  }

  /// @dev Burn ERC1155 token to redeem ERC20 token back.
  /// @param id Token id to burn
  /// @param amount Token amount to burn
  function burn(uint id, uint amount) external nonReentrant returns (uint) {
    if (amount == uint(-1)) {
      amount = balanceOf(msg.sender, id);
    }
    _burn(msg.sender, id, amount);
    IStakingRewards(staking).withdraw(amount);
    IStakingRewards(staking).getReward();
    IERC20(underlying).safeTransfer(msg.sender, amount);
    uint stRewardPerToken = id;
    uint enRewardPerToken = IStakingRewards(staking).rewardPerToken();
    uint stReward = stRewardPerToken.mul(amount).divCeil(1e18);
    uint enReward = enRewardPerToken.mul(amount).div(1e18);
    if (enReward > stReward) {
      IERC20(reward).safeTransfer(msg.sender, enReward.sub(stReward));
    }
    return enRewardPerToken;
  }
}
