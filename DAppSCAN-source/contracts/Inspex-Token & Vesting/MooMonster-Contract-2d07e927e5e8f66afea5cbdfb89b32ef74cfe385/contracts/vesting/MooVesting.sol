// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract MOOVesting is AccessControl {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  // category
  enum CategoryNames {
    EMPTY,
    ANGEL,
    SEED,
    PRIVATE,
    PUBLIC,
    TEAM,
    PARTNER,
    MARKETING,
    INCENTIVE,
    ECOSYSTEM
  }
  struct CategoryType {
    uint256 totalSteps;
    uint256 cliffAfterTGE; //unix format
    uint256 stepTime; // unix format
    uint256 percentBefore; // decimals = 2
    uint256 percentAfter; // decimals = 2
  }
  mapping(CategoryNames => CategoryType) public categories;

  // investor
  struct InvestorTokens {
    address investor;
    CategoryNames category;
    uint256 tokenAmount;
  }
  mapping(bytes32 => uint256) public alreadyRewarded;

  // contract settings
  address public immutable token;
  bytes32 public immutable mercleRoot;
  uint256 public immutable tgeTimestamp;

  uint256 public executeTime;

  // claim state
  mapping(bytes32 => bool) public tgeIsClaimed;
  mapping(bytes32 => uint256) public lastClaimedStep;

  mapping(bytes32 => address) public receiverAddress;

  event Claim(
    address indexed target,
    uint256 indexed category,
    uint256 amount,
    bytes32[] merkleProof,
    uint256 resultReward,
    uint256 timestamp
  );
  event TgeClaim(
    address indexed target,
    uint256 indexed category,
    uint256 value,
    uint256 timestamp
  );
  event StepClaim(
    address indexed target,
    uint256 indexed category,
    uint256 indexed step,
    uint256 value,
    uint256 timestamp
  );
  event SetPendingReceiverAddress(
    address indexed user,
    address indexed receiver
  );
  event SetTargetReceiverAddress(
    address indexed target,
    uint256 indexed category,
    uint256 amount,
    address indexed receiver
  );

  event QueueEmergencyWithdraw(uint256 executeTime);
  event EmergencyWithdraw(address receiver, uint256 amount);

  constructor(
    address _token,
    bytes32 _mercleRoot,
    uint256 _tgeTimestamp
  ) public {
    require(_token != address(0), "MOOVesting: zero token address");
    require(_mercleRoot != bytes32(0), "MOOVesting: zero mercle root");
    require(
      _tgeTimestamp >= block.timestamp,
      "MOOVesting: wrong TGE timestamp"
    );

    token = _token;
    mercleRoot = _mercleRoot;
    tgeTimestamp = _tgeTimestamp;

    // rounds settings
    categories[CategoryNames.ANGEL] = CategoryType({
      totalSteps: 12,
      cliffAfterTGE: 3 * 30 days,
      stepTime: 30 days,
      percentBefore: 4_00,
      percentAfter: 8_00 // 4.00% + 8.00% * 12 = 100%
    });
    categories[CategoryNames.SEED] = CategoryType({
      totalSteps: 10,
      cliffAfterTGE: 2 * 30 days,
      stepTime: 30 days,
      percentBefore: 8_00,
      percentAfter: 9_20 // 8.00% + 9.20% * 10 = 100%
    });
    categories[CategoryNames.PRIVATE] = CategoryType({
      totalSteps: 9,
      cliffAfterTGE: 2 * 30 days,
      stepTime: 30 days,
      percentBefore: 11_00,
      percentAfter: 9_88 // 11.00% + 9.88% * 9 = 99.92%
    });
    categories[CategoryNames.PUBLIC] = CategoryType({
      totalSteps: 4,
      cliffAfterTGE: 0,
      stepTime: 30 days,
      percentBefore: 20_00,
      percentAfter: 20_00 // 20.00% + 20.00% * 4 = 100%
    });
    categories[CategoryNames.TEAM] = CategoryType({
      totalSteps: 34,
      cliffAfterTGE: 3 * 30 days,
      stepTime: 30 days,
      percentBefore: 0,
      percentAfter: 2_94 // 0.00% + 2.94% * 34 = 99.96%
    });
    categories[CategoryNames.PARTNER] = CategoryType({
      totalSteps: 34,
      cliffAfterTGE: 2 * 30 days,
      stepTime: 30 days,
      percentBefore: 0,
      percentAfter: 2_94 // 0.00% + 2.94% * 34 = 99.96%
    });
    categories[CategoryNames.MARKETING] = CategoryType({
      totalSteps: 19,
      cliffAfterTGE: 0,
      stepTime: 30 days,
      percentBefore: 5_00,
      percentAfter: 5_00 // 5% + 5% * 19 = 100.00%
    });
    categories[CategoryNames.INCENTIVE] = CategoryType({
      totalSteps: 20,
      cliffAfterTGE: 14 days,
      stepTime: 30 days,
      percentBefore: 0,
      percentAfter: 5_00 // 0% + 5% * 20 = 100.00%
    });
    categories[CategoryNames.ECOSYSTEM] = CategoryType({
      totalSteps: 40,
      cliffAfterTGE: 30 days,
      stepTime: 30 days,
      percentBefore: 0,
      percentAfter: 2_50 // 0% + 2.5% * 40 = 100.00%
    });

    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  function checkClaim(
    address _target,
    uint256 _category,
    uint256 _amount,
    bytes32[] calldata _merkleProof
  ) external view returns (bool) {
    return (_verify(_target, _category, _amount, _merkleProof));
  }

  function claim(
    address _target,
    uint256 _category,
    uint256 _amount,
    bytes32[] calldata _merkleProof
  ) external returns (uint256 _claimResult) {
    require(
      _verify(_target, _category, _amount, _merkleProof),
      "MOOVesting: Invalid proof or wrong data"
    );
    require(
      block.timestamp >= tgeTimestamp,
      "MOOVesting: TGE has not started yet"
    );

    CategoryType memory category = categories[CategoryNames(_category)];

    uint256 reward = 0;

    bytes32 targetHash = keccak256(
      abi.encodePacked(_target, _category, _amount)
    );

    // claim TGE reward
    if (tgeIsClaimed[targetHash] == false) {
      reward = reward.add(_amount.mul(category.percentBefore).div(100_00));
      tgeIsClaimed[targetHash] = true;

      emit TgeClaim(_target, _category, reward, block.timestamp);
    }

    uint256 secondRelease = tgeTimestamp.add(category.cliffAfterTGE);
    uint256 rewarded = alreadyRewarded[targetHash];
    // claim reward after TGE

    for (
      uint256 i = lastClaimedStep[targetHash] + 1;
      i <= category.totalSteps;
      i++
    ) {
      uint256 addedAmount = 0;

      if (secondRelease.add(category.stepTime.mul(i)) <= block.timestamp) {
        lastClaimedStep[targetHash] = i;

        if (i == category.totalSteps) {
          // last step release all
          addedAmount = _amount.sub(rewarded.add(reward));
        } else {
          addedAmount = _amount.mul(category.percentAfter).div(100_00);
        }

        reward = reward.add(addedAmount);

        emit StepClaim(_target, _category, i, addedAmount, block.timestamp);
      } else {
        break;
      }
    }

    require(reward > 0, "MOOVesting: no tokens to claim");

    uint256 resultReward = 0;

    // if reward overlimit (security check)
    if (rewarded.add(reward) > _amount) {
      resultReward = _amount.sub(
        rewarded,
        "MOOVesting: no tokens to claim (security check)"
      );
    } else {
      resultReward = reward;
    }

    alreadyRewarded[targetHash] = alreadyRewarded[targetHash].add(resultReward);
    if (receiverAddress[targetHash] != address(0))
      IERC20(token).safeTransfer(receiverAddress[targetHash], resultReward);
    else IERC20(token).safeTransfer(_target, resultReward);

    emit Claim(
      _target,
      _category,
      _amount,
      _merkleProof,
      resultReward,
      block.timestamp
    );

    return (resultReward);
  }

  function _verify(
    address _target,
    uint256 _category,
    uint256 _amount,
    bytes32[] memory _merkleProof
  ) internal view returns (bool) {
    bytes32 node = keccak256(abi.encodePacked(_target, _category, _amount));
    return (MerkleProof.verify(_merkleProof, mercleRoot, node));
  }

  function setReceiverAddress(
    uint256 _category,
    uint256 _amount,
    bytes32[] calldata _merkleProof,
    address _newReceiver
  ) external {
    require(_newReceiver != address(0), "MOOVesting: receiver zero address");
    require(
      _verify(_msgSender(), _category, _amount, _merkleProof),
      "MOOVesting: Invalid proof or wrong data"
    );

    bytes32 targetHash = keccak256(
      abi.encodePacked(_msgSender(), _category, _amount)
    );

    receiverAddress[targetHash] = _newReceiver;

    emit SetTargetReceiverAddress(
      _msgSender(),
      _category,
      _amount,
      _newReceiver
    );
  }

  function queueEmergencyWithdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
    // Emergency
    require(
      block.timestamp >= tgeTimestamp + (41 * 30 days), // emergencyWithdraw can be also executed after 41 months
      "MOOVesting: Emergency withdraw should perform 41 months after TGE"
    );
    executeTime = block.timestamp + 24 hours; // Timelock 24 hours
    emit QueueEmergencyWithdraw(executeTime);
  }

  function emergencyWithdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
    require(
      executeTime != 0 && block.timestamp >= executeTime,
      "MOOVesting: Invalid Timelock"
    );

    uint256 totalAmount = IERC20(token).balanceOf(address(this));
    IERC20(token).safeTransfer(_msgSender(), totalAmount);

    executeTime = 0;

    emit EmergencyWithdraw(_msgSender(), totalAmount);
  }
}
