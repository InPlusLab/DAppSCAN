pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract EarlyRewards is Ownable {
  using SafeMath for uint256;

  bool public canSetReward;
  address public IDLE;
  address public ecosystemFund;
  uint256 public claimDeadline;
  mapping (address => uint256) public rewards;

  constructor(address _idle, address _ecosystemFund, uint256 _claimDeadline) public {
    IDLE = _idle;
    ecosystemFund = _ecosystemFund;
    claimDeadline = _claimDeadline;
    canSetReward = true;
  }

  function setRewards(address[] calldata _recipients, uint256[] calldata _amounts) external onlyOwner {
    require(canSetReward, "CANNOT_SET");
    require(_recipients.length == _amounts.length, "LEN_DIFF");

    for (uint256 i = 0; i < _recipients.length; i++) {
      if (_recipients[i] != address(0) && _amounts[i] != 0) {
        rewards[_recipients[i]] = _amounts[i];
      }
    }
  }

  function stopSettingRewards() external onlyOwner {
    canSetReward = false;
  }

  function claim() external returns (uint256 reward) {
    reward = rewards[msg.sender];
    require(reward != 0, "!AUTH");
    rewards[msg.sender] = 0;
    ERC20(IDLE).transfer(msg.sender, reward);
  }

  function emergencyWithdrawal(address token, address to, uint256 amount) external onlyOwner {
    // IDLE can only be transferred by owner to Ecosystem fund contract after a deadline
    require(token != IDLE || block.timestamp >= claimDeadline, "TOO_EARLY");
    ERC20 idle = ERC20(IDLE);
    if (token == IDLE) {
      idle.transfer(ecosystemFund, idle.balanceOf(address(this)));
      return;
    }

    // all other tokens can be transferred if any
    ERC20(token).transfer(to, amount);
  }
}
