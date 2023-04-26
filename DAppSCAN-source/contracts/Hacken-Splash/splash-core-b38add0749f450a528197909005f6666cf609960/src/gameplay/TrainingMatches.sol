// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "oz-contracts/access/Ownable.sol";

import "./MatchMaker.sol";
import "../utils/Errors.sol";
import "../interfaces/IRegistry.sol";

contract TrainingMatches is Ownable, MatchMaker {
  /* IRegistry registry from MatchMaker */
  
  // Upgrade card drop rate, out of 10**6
  uint256 dropRate = 1000;

  mapping(address => mapping(uint8 => uint256)) public upgradeClaims;
  mapping(address => address) private _opponents;

  event MatchFinished(address user, uint8 result);
  event UpgradeCardDropped(address user, uint8 cardType);

  modifier checkStarters() {
    // This will revert if starters are not ready
    registry.management().checkStarters(msg.sender);
    _;
  }
  
  constructor(IRegistry registryAddress) MatchMaker(registryAddress) { }

  // ############## SETTERS ############## //

  function setDropRate(uint256 newDropRate) external onlyOwner {
    dropRate = newDropRate;
  }

  // ############## CLAIMS ############## //
  
  /**
    @notice Claims upgrade packs dropped randomly in training matches
    @dev TrainingMatches contract needs to be authorized by NC1155 to mint
  */
  function claimUpgradePacks(uint8 cardType) external returns(uint256 claimedTokens) {
    uint256 cardsToClaim = upgradeClaims[msg.sender][cardType]; 
    
    if (cardsToClaim == 0) {
      return 0;
    }

    delete upgradeClaims[msg.sender][cardType];
    registry.sp1155().mint(msg.sender, cardType, cardsToClaim, "");
  }

  // ############## TRAINING ############## //

  /**
    @notice Makes before training preparations and request a random number to use in match
    @dev Requires TrainingMatches contract to be authorized by RNG contract
    @dev Requires team to not be in the cooldown
    @dev Requires each player in the defaultFive to be ready (Management.checkStarters)
  */
  function requestTrainingRandomness(address opponent) external checkStarters {
    require(opponent != address(0), Errors.ZERO_ADDRESS);

    _opponents[msg.sender] = opponent;
    registry.rng().requestBlockRandom(msg.sender);
  }


  /**
    @notice Checks the random for training and plays a match
    @dev Challenges the opponent stored in _opponents and upgrades players
    depending on the score
    @dev Requires TrainingMatches contract to be authorized by RNG contract
    @dev Emits MatchFinished
    @dev Drops a upgrade card with a 0.1% percent chance and emits UpgradeCardDropped
  */
  function train() external checkStarters {
    require(_opponents[msg.sender] != address(0), Errors.ZERO_ADDRESS);

    // Generate the random
    registry.rng().checkBlockRandom(msg.sender);
    // It'll revert if there's no random number
    uint256 trainingRandomness = registry.rng().getBlockRandom(msg.sender);

    (uint8 score, uint256 atkUpgrade, uint256 defUpgrade) = matchMaker({
      enableMorale: true,
      playerOne: msg.sender,
      playerTwo: _opponents[msg.sender],
      randomness: trainingRandomness
    });

    emit MatchFinished(msg.sender, score);

    if (score >= 4) {  
      if(trainingRandomness % 1_000_000 < dropRate) {
        uint8 rewardCardType = uint8(trainingRandomness % 10);
        upgradeClaims[msg.sender][rewardCardType] += 1;
        emit UpgradeCardDropped(msg.sender, rewardCardType);
      }
        
      registry.management().upgradeAllPlayers({
        user: msg.sender,
        nthField: trainingRandomness % 5,
        atkAmount: uint24(atkUpgrade),
        defAmount: uint24(defUpgrade)
      });
    }

    registry.management().afterTraining(msg.sender, score >= 4);

    delete _opponents[msg.sender];
    registry.rng().resetBlockRandom(msg.sender);
  }
}