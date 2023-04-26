// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

/**
  Struct to hold information about a team
  @member initialized:    To check if team exists
  @member morale:         Morale score, between 80 and 120
  @member wins:           Win count
  @member lastChallenge:  Last challenge time
  @member defaultFive:    Selected five players that we'll use in matches
*/
struct Team {
  bool initialized;
  uint8 morale;
  uint16 wins;
  uint48 lastChallenge;
  uint256[5] defaultFive;
}

/**
  Struct to hold information about a player
  @member locked:         If the player is locked
  @member status:         Status of the player (0-rookie, 1-veteran)
  @member academyType:    Academy type
  @member potential:      Maximum point a player can reach
  @member rentFinish:     Rented player's expire time, 0 means not rented
  @member lastChallenge:  Last challenge time for the player
  @member leftToExpire:   For rookies, time until veteran phase; for veteran
                          remaining match count
  @member stats:          Attack & defence stats of the player

  @dev Each stat of a player is 100_000 max
  @dev Players are locked in tournaments
*/
struct Player {
  bool locked;
  uint8 status;
  uint16 academyType;
  uint24 potential;
  uint48 rentFinish;
  uint48 lastChallenge;
  uint48 leftToExpire;
  uint24[10] stats;
}

interface IManagement {
  function getTeamOf(address user) external view returns (Team memory);
  function getAtkAndDef(address user) external view returns (uint256, uint256);

  function checkStarters(address user) external view;
  function checkStarters(address user, uint256 matchCount, uint48 endTime) external view;
  function checkForSale(address user, uint256 playerId) external view;
  function checkForBuy(address user, uint256 playerId) external view;
  
  function upgradeAllPlayers(address user, uint256 nthField, uint24 atkAmount, uint24 defAmount) external;
  
  function afterTraining(address user, bool won) external;
  function afterTournamentRound(address userOne, address userTwo) external;
  
  function lockDefaultFive(address user) external;
  function lockVeteranBatch(address user, uint256[] calldata ids) external;
  function lockRetiredBatch(address user, uint256[] calldata ids) external;
  function unlockVeteranBatch(address user, uint256[] calldata ids) external;
  function unlockRetiredBatch(address user, uint256[] calldata ids) external;
  function unlockDefaultFive(address user) external;

  function transferPlayerFrom(address from, address to, uint256 playerId) external;
  function rentPlayerFrom(address from, address to, uint256 playerId, uint48 duration) external;
}
