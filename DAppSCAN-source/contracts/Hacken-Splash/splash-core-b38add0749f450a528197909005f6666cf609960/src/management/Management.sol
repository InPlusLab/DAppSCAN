// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "oz-contracts/utils/structs/EnumerableSet.sol";
import "oz-contracts/access/Ownable.sol";

import "../utils/Errors.sol";
import "../interfaces/IRegistry.sol";

contract Management is Ownable, IManagement {
  using EnumerableSet for EnumerableSet.UintSet;

  IRegistry registry;

  // Max num of rookie players one coach can have
  uint256 constant MAX_PLAYER_COUNT = 45;
  // After expire time rookie players turn into veteran
  uint256 constant EXPIRE_TIME = 12 weeks;
  // Number of digits we'll use for playerID
  uint256 constant ID_MODULUS = 10**20;
  // Maximum point for each stat while creating a player
  uint24 constant MAX_START = 25_000;
  // Minimum amount of potential for player
  uint24 constant MIN_POTENTIAL = 40_000;
  // The amount one upgrade card upgrades a stat
  uint24 constant CARD_UPGRADE_AMOUNT = 10_000;
  // Academies to create in the constructor
  uint256 constant INIT_ACADEMY_COUNT = 3;
  // Match limit of a veteran player
  uint48 constant VETERAN_MATCH_COUNT = 100;

  uint256 trainingInterval = 4 hours;

  event AcademyAdded    (uint256 indexed academyId);
  event AcademyRemoved  (uint256 indexed academyId);

  event TeamRegistered  (address indexed player);

  event PlayerMinted    (uint256 indexed playerId);
  event PlayerVeteran   (uint256 indexed playerId);
  event PlayerRented    (address from, address to, uint48 duration);

  /**
    @notice Checks for the arrays repetitive members
    @param arr : Array to check
    @dev Excludes the 0 ids
  */
  modifier isUniqueSet(uint256[5] memory arr) {
    for (uint256 i = 0; i < 5; i++) {
      for (uint256 j = 0; j < 5; j++) {
        if (i == j) {
          continue;
        } else if (arr[i] == arr[j] && arr[i] != 0) {
          require(false, Errors.DUP_PLAYER);
        }
      }
    }
    _;
  }

  modifier authorized() {
    require(registry.authorized(msg.sender), Errors.NOT_AUTHORIZED);
    _;
  }

  mapping(address => Team)    public userToTeam;
  mapping(uint256 => Player)  public idToPlayer;
  mapping(uint256 => address) public idToCoach;

  EnumerableSet.UintSet internal academies;

  constructor(IRegistry registryAddress) { 

    registry = IRegistry(registryAddress);

    for (uint256 i = 0; i < INIT_ACADEMY_COUNT; i++) {
      addAcademy();
    }
  }

  // ############## SETTERS ############## //

  function setTrainingInterval(uint256 newTrainingInterval) external onlyOwner {
    trainingInterval = newTrainingInterval;
  }

  // ############## ACADEMY ############## //

  /**
    @notice Add an academy
    @dev Academies can be added and removed, so we're storing digests
    Owner is trusted to not call the function where collusions may happen
    @dev Emits AcademyAdded
  */
  function addAcademy() public onlyOwner {
    
    uint256 academyId = uint256(
      keccak256(abi.encodePacked(academies.length(), block.timestamp))
    ) % ID_MODULUS;

    academies.add(academyId);
    emit AcademyAdded(academyId);
  }

  /**
    @notice Removes an academy
    @param academyId: Academy to remove
    @dev Emits AcademyRemoved
  */
  function removeAcademy(uint256 academyId) public onlyOwner {
    
    academies.remove(academyId);
    emit AcademyRemoved(academyId);
  }

  // ############## TEAM ############## //

  /** @dev Getter for default five */
  function getDefaultFive(address user) external view returns (uint256[5] memory) {
    
    return userToTeam[user].defaultFive;
  }

  /**
    @notice Registers a team
    @dev This is required for checks for team existence
    Any other team operation requires a initialized team
    @dev Emits TeamRegistered 
  */
  function registerTeam() external {
    
    require(!userToTeam[msg.sender].initialized, Errors.TEAM_NOT_INIT);

    userToTeam[msg.sender] = Team({
      initialized: true,
      morale: 100,
      wins: 0,
      lastChallenge: uint48(block.timestamp) - 5 hours,
      defaultFive: [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)]
    });

    emit TeamRegistered(msg.sender);
  }

  // ############## STARTER PACKS ############## //

  /**
    @notice Request random number from Chainlink to open a pack
    Burns a player pack
    @dev Requires the Management to be authorized by RNG
  */
  function requestOpenPackRandomness() external {
    require(registry.sp1155().balanceOf(msg.sender, 10) > 0, "sp1155 bal");
    require(userToTeam[msg.sender].initialized, "not init");
    require(registry.sp721().balanceOf(msg.sender) <= MAX_PLAYER_COUNT, "p count");

    registry.rng().requestChainlinkRandom(msg.sender);
    registry.sp1155().burn(msg.sender, 10, 1);
  }

  /** 
    @notice Opens the player pack and creates 5 players,
    resets random afterwards
    @dev Requires the Management to be authorized by RNG
  */
  function openPack() external {
    uint256 randomness = registry.rng().getChainlinkRandom(msg.sender);
    require(randomness != 0, "");

    for (uint256 i = 0; i < 5; i++) {
      uint256 playerDigest = uint256(keccak256(abi.encodePacked(randomness, i)));
      _createPlayer(playerDigest);
    }

    registry.rng().resetChainlinkRandom(msg.sender);
  }

  // ############## PLAYER ############## //

  /** @dev Getter for player stats */
  function getStats(uint256 playerId) external view returns (uint24[10] memory) {
    return idToPlayer[playerId].stats;
  }

  /**
    @notice Extracts 10 base stats from Chainlink generated ID
    and creates a Player instance then mints a ERC721 player NFT
    @dev Requires Management to be authorized by NC721
    @dev Emits PlayerMinted
  */
  function _createPlayer(uint256 randomness) private {
    uint256 academyId = academies.at(randomness % academies.length());
    uint24[10] memory statsList;

    // Set each stat a random value between 0 and MAX_START * 1000
    for (uint256 i = 0; i < 10; i++) {
      uint24 statPart = _modByDigit(randomness, i * 2, 2) * 1000;
      statsList[i] = _calculatePower(statPart);

      assert(statsList[i] < MAX_START);
    }

    idToPlayer[randomness] = Player({
      locked: false,
      status: 0,
      academyType: uint16(academyId),
      potential: MIN_POTENTIAL + uint24(randomness % 60_000),
      rentFinish: 0,
      lastChallenge: uint48(block.timestamp) - 5 hours,
      leftToExpire: uint48(block.timestamp + EXPIRE_TIME),
      stats: statsList
    });

    idToCoach[randomness] = msg.sender;
    registry.sp721().safeMint(msg.sender, randomness);
    emit PlayerMinted(randomness);
  }

  /**
    @notice Upgrades a player, player's potential being the upper bound
    @param playerId: ID of the playuer
    @param stat: Index of the stat, see NC1155 for how they're distributed
    @param amount: Amount of points to upgrade
  */
  function _upgradePlayer(
    uint256 playerId,
    uint256 stat,
    uint24 amount
  ) private {
    require(idToCoach[playerId] != address(0), "");

    Player storage player = idToPlayer[playerId];

    player.stats[stat] += amount;

    if (player.stats[stat] >= player.potential) 
      player.stats[stat] = player.potential;
  }

  /**
    @notice Makes a rookie player veteran if the conditions are met
    @param playerId: ID of the player
    @dev Emits PlayerVeteran
  */
  function makeVeteran(uint256 playerId) external {
    require(idToCoach[playerId] == msg.sender, "");
    require(idToPlayer[playerId].status == 0, "");
    require(idToPlayer[playerId].leftToExpire <= block.timestamp);

    idToPlayer[playerId].status = 1;
    idToPlayer[playerId].leftToExpire = VETERAN_MATCH_COUNT;

    emit PlayerVeteran(playerId);
  }

  // ############## RENTS ############## //

  /**
    Claims back the rented player when the period finishes

    @param playerId:    Player to claim
    @param to:          Address to claim to    
  */
  function claimRented(uint256 playerId, address to) external {
    require(idToCoach[playerId] != to, "");
    require(idToPlayer[playerId].rentFinish < block.timestamp, "");
    require(registry.sp721().ownerOf(playerId) == to, "");

    idToPlayer[playerId].rentFinish = 0;
    idToCoach[playerId] = to;
  }

  // ############## UPGRADE PACKS ############## //

  /**
    @notice Upgrade a player by burning an upgrade card
    @param id: ID of the upgrade card, see NC1155
    @param playerId: Player to ugprade
    @dev Requires Management to be authorized by NC1155 contract
  */
  function useUpgradeCard(uint256 id, uint256 playerId) external {
    require(registry.sp1155().balanceOf(msg.sender, id) >= 1, "");
    require(idToCoach[playerId] == msg.sender, "");
    require(idToPlayer[playerId].status == 0, "");

    // Burn 1 card
    registry.sp1155().burn(msg.sender, id, 1);

    _upgradePlayer(playerId, id, CARD_UPGRADE_AMOUNT);
  }

  // ############## MATCHES ############## //

  /**
    @notice Sets the default team of the coach
    @param defaultFive: Array of playerIds
    @dev No repetitive ids allowed (unless it is 0)
    @dev Allows defaultFives with less than 5 players,
    as it is not possible to sell a player in the defaultFive
    so that one can remove their player from def.five and sell 
    it afterwards.
    We then have to check for all players before entering a match
    @dev It won't allow changing default five while players are locked,
    in that case another function called substituteLocked will be used
    to make sure team is valid after next match
  */
  function setDefaultFive(uint256[5] memory defaultFive) external isUniqueSet(defaultFive) {
    require(userToTeam[msg.sender].initialized, "");
    // Checking first player's locked fields to see if in tournament
    require(!idToPlayer[userToTeam[msg.sender].defaultFive[0]].locked, "");

    // For each player check if coach of the player is right
    for (uint256 i = 0; i < 5; i++) {
      require(
        defaultFive[i] == 0 || idToCoach[defaultFive[i]] == msg.sender,
        ""
      );

      require(!idToPlayer[defaultFive[i]].locked, "");
    }

    userToTeam[msg.sender].defaultFive = defaultFive;
  }

  /**
    @notice Substitutes a player with another
    @dev Only callable in tournaments
    @dev It should prevent changing default five to a invalid one 
    during tournaments
  */
  function substituteLocked(uint256 idx, uint256 newPlayer) external {
    require(newPlayer != 0, Errors.INVALID_PLAYER);

    // Checking first player's locked fields to see if in tournament
    require(
      idToPlayer[userToTeam[msg.sender].defaultFive[0]].locked,
      Errors.CALLABLE_IN_TOURNAMENT
    );

    uint256[5] memory defaultFive = userToTeam[msg.sender].defaultFive;
    for (uint256 i = 0; i < 5; i++) {
      require(defaultFive[i] != newPlayer, Errors.DUP_PLAYER);
    }

    idToPlayer[defaultFive[idx]].locked = false;
    userToTeam[msg.sender].defaultFive[idx] = newPlayer;
    idToPlayer[newPlayer].locked = true;
  }

  // ############## IMANAGEMENT ############## //

  /**
    @notice Getter function for retrieving a coach's team
    @dev Checks if team is initialized FIXME (Not sure about this one)
  */
  function getTeamOf(address user) external view override returns (Team memory) {
    require(userToTeam[user].initialized, "");
    return userToTeam[user];
  }

  function checkStarters(address user) external view override {
    _checkStarters(user, 1, 0);
  }

  function checkStarters(
    address user,
    uint256 matchCount,
    uint48 endTime
  ) external view override {
    _checkStarters(user, matchCount, endTime);
  }

  /**
    @notice Checks coach's team's starters and reverts if any of the players
    are ready for a match

    @param user:        User to check
    @param matchCount:  Match count to check availability for. It is 1 for training mathces by default
    @param endTime:     (If it is a tournament) End of the timeframe where player must be available

    @dev For each player, conditions are:
      - Player must exist
      - Caller must be the coach of the player
      - Player mustn't be locked
      - Player mustn't be in cooldown
      - (If rented) player's rent mustn't be expired
      - Player mustn't hit its match limit

    @dev Cooldown is checked separately to make sure it's not possible to create
    multiple teams and train & transfer the same player over and over.
  */
  function _checkStarters(
    address user,
    uint256 matchCount,
    uint48 endTime
  ) private view {
    // It is either a training match or a tournament,
    // require(matchCount == 1 || endTime > block.timestamp, "");

    uint256[5] memory starters = userToTeam[user].defaultFive;

    for (uint256 i = 0; i < 5; i++) {
      uint256 playerId = starters[i];
      require(playerId != 0, "");
      require(idToCoach[playerId] == user, "");

      Player memory player = idToPlayer[playerId];

      require(!player.locked, "");
      require(
        player.lastChallenge + trainingInterval <= uint48(block.timestamp),
        ""
      );

      // If rented check time
      require(
        player.rentFinish == 0 || player.rentFinish >= uint48(block.timestamp),
        ""
      );

      // If endTime is null, this is a training match; check for block.timestamp
      uint48 deadline = endTime > 0 ? endTime : uint48(block.timestamp);

      // If rookie check for expire date, if veteran check for remaining match count
      require(
        player.leftToExpire >= (player.status == 0 ? deadline : matchCount),
        ""
      );
    }
  }

  /**
    @notice Before sale checks if:
      - Player is in default five
      - Player is locked (in tournament)
      - Caller and coach matches (aka if it's already rented)
  */
  function checkForSale(address user, uint256 playerId) external view override {
    require(!_inDefaultFive(playerId), "");
    require(!idToPlayer[playerId].locked, "");
    require(idToCoach[playerId] == user, "");
  }

  /**
    @notice Before buying/renting a card checks if:
      - Player is in default five,
      - Player is locked (in tournament)
      - Caller isn't the owner of the NFT

    @dev It is possible to list a card and enter a tournament with it and
    blocking this function in the process. In order not to make more external calls
    we are passing this responsibility to the front-end.
  */
  function checkForBuy(address user, uint256 playerId) external view override {
    require(!_inDefaultFive(playerId), "");
    require(!idToPlayer[playerId].locked, "");
    require(idToCoach[playerId] != user, "");
  }

  function lockDefaultFive(address user) external override authorized {
    
    for (uint256 i = 0; i < 5; i++) {
      uint256 playerId = userToTeam[user].defaultFive[i];
      idToPlayer[playerId].locked = true;
    }
  }

  function lockVeteranBatch(
    address user, 
    uint256[] calldata ids
  ) external override authorized {

    for (uint256 i = 0; i < ids.length; i++) {
      Player storage player = idToPlayer[ids[i]];
      require(idToCoach[ids[i]] == user, Errors.NOT_COACH);
      require(!player.locked, Errors.PLAYER_LOCKED);
      require(player.status == 1 && player.leftToExpire > 0, Errors.PLAYER_NOT_VETERAN);

      player.locked = true;
    }
  }

  function lockRetiredBatch(
    address user,
    uint256[] calldata ids
  ) external override authorized {

    for(uint256 i = 0; i < ids.length; i++) {
      Player storage player = idToPlayer[ids[i]];
      require(idToCoach[ids[i]] == user, Errors.NOT_COACH);
      require(!player.locked, Errors.PLAYER_LOCKED);
      require(player.status == 1 && player.leftToExpire == 0, Errors.PLAYER_NOT_RETIRED);

      player.locked = true;
    }
  }

  function unlockVeteranBatch(
    address user,
    uint256[] calldata ids
  ) external override authorized {

    for(uint256 i = 0; i < ids.length; i++) {
      Player storage player = idToPlayer[ids[i]];
      require(idToCoach[ids[i]] == user, Errors.NOT_COACH);
      require(player.locked, Errors.PLAYER_NOT_LOCKED);
      player.locked = false;
    }
  }

  function unlockRetiredBatch(
    address user,
    uint256[] calldata ids
  ) external override authorized {

    for(uint256 i = 0; i < ids.length; i++) {
      Player storage player = idToPlayer[ids[i]];
      require(idToCoach[ids[i]] == user, Errors.NOT_COACH);
      require(player.locked, Errors.PLAYER_NOT_LOCKED);
      player.locked = false;
    }
  }

  function unlockDefaultFive(address user) external override authorized {
    
    for (uint256 i = 0; i < 5; i++) {
      uint256 playerId = userToTeam[user].defaultFive[i];

      idToPlayer[playerId].locked = false;
    }
  }

  /**
    @notice Upgrades all players of one coach.
    This is done by upgrading one stat of each player
    This stat is nth field of attack or defence depending of player's
    position
    @dev It will skip the veteran players
    @param user: Coach to upgrade players of
    @param nthField: Index of the field to ugprade, lesser than 5
    @param atkAmount: Amount to upgrade if the player is attacker
    @param defAmount: Amount to upgrade if the player is defencer
  */
  function upgradeAllPlayers(
    address user,
    uint256 nthField,
    uint24 atkAmount,
    uint24 defAmount
  ) external override authorized {

    uint256[5] memory players = userToTeam[user].defaultFive;

    for (uint256 i = 0; i < 5; i++) {
      if (idToPlayer[players[i]].status == 1) continue;

      // Upgrade nth field or either attack or
      // defence depending on the player position
      uint256 stat = i < 3 ? nthField : nthField + 5;

      _upgradePlayer(players[i], stat, i < 3 ? atkAmount : defAmount);
    }
  }

  function afterTraining(address user, bool won) external override authorized {
    
    Team storage team = userToTeam[user];
    require(team.initialized, "");

    uint256 hoursOut = (block.timestamp - team.lastChallenge) / 8 hours;

    if (hoursOut == 0) {
      team.morale += 4;
    } else if (hoursOut == 1) {
      team.morale += 2;
    } else if (hoursOut == 3) {
      team.morale -= 2;
    } else if (hoursOut == 4) {
      team.morale -= 4;
    } else if (hoursOut > 4) {
      team.morale -= 20;
    }

    // Clamp morale between 80 and 120
    if (team.morale > 120) team.morale = 120;
    if (team.morale < 80) team.morale = 80;

    if (won) userToTeam[user].wins++;

    // Reset last challenge for both team and each player in default five
    team.lastChallenge = uint48(block.timestamp);
    for (uint256 i = 0; i < 5; i++)
        idToPlayer[team.defaultFive[i]].lastChallenge = uint48(block.timestamp);
  }

  /**
    @notice Updates legendary players' deadlines after tournament round
  */
  function afterTournamentRound(address userOne, address userTwo) external override authorized {
    
    uint256[5] memory startersOne = userToTeam[userOne].defaultFive;
    uint256[5] memory startersTwo = userToTeam[userTwo].defaultFive;

    for (uint256 i = 0; i < 5; i++) {
      if (idToPlayer[startersOne[i]].status == 1)
        idToPlayer[startersOne[i]].leftToExpire -= 1;
      if (idToPlayer[startersTwo[i]].status == 1)
        idToPlayer[startersTwo[i]].leftToExpire -= 1;
    }
  }

  /**
    @notice Changes the coach and rent duration after rent
    @dev Emits PlayerRented
  */
  function rentPlayerFrom(
    address from,
    address to,
    uint256 playerId,
    uint48 duration
  ) external override authorized {
    
    require(registry.sp721().ownerOf(playerId) == from, "");
    require(idToCoach[playerId] == from, "");

    idToCoach[playerId] = to;
    idToPlayer[playerId].rentFinish = uint48(block.timestamp) + duration;

    emit PlayerRented(from, to, duration);
  }

  function transferPlayerFrom(
    address from,
    address to,
    uint256 playerId
  ) external override authorized {
    
    require(from == idToCoach[playerId] || from == address(0), "");
    require(!idToPlayer[playerId].locked, "");

    idToCoach[playerId] = to;
  }

  /**
    @notice Gets attack and defence points of a user
    @dev To use less resources we store two 6 digit numbers on
    mainScore and secondaryScore
    => 345652-123324 => 345652: defence score, 123324: attack score
    @dev Each player effects the attack & defence score depending on where they are
    in the default five. E.g attack players effect attack score 3 times more than defence score
    and vice versa.
    @dev Suppose we have 5 players [a,b,c,d,e] where a,b are attackers; c is joker and d,e are defenders.
    Attack and defence scores are calculated so that
    1. We take attack and defence stat sums' averages of players
      SOAS -> Sum Of Attack Stats
      SODS -> Sum Of Defence Stats
      Attacker attack points = [SOAS(a) + SOAS(b) + SOAS(c)] / 3
      Attacker defence points = [SODS(a) + SODS(b)] / 2
      Defender attack points = [SOAS(d) + SOAS(e)] / 2
      Defender defence points = [SODS(c) + SODS(d) + SODS(e)] / 3
    2. Attack/Defence point of the team is 0.75 * relevant player's sum + 0.25 * irrelevant player's sum
      Attack Score = Attacker attack points * 0.75 + Defender attack points * 0.25
      Defence Score = Defender defence points * 0.75 + Attacker defence points * 0.25
    3. Result is multiplied by (3/20) to down-scale to 75_000
    @dev Remaining 25_000 is the academy effect and is inversely proportial to diffent academies 
    a default five has. The formula is 5000 * (6 - (differentAcademyCount))
    @dev These operations can be expressed such as
    Attack score  =     [6*SOAS(a,b,c) + 3SOAS(c,d,e)] / 160 + 25000
    Defence score =     [6*SODS(c,d,e) + 3SODS(c,d,e)] / 160 + 25000
  */
  function getAtkAndDef(address user) external view override returns (uint256, uint256) {
    
    uint256 mainScore = 0;
    uint256 secondaryScore = 0;

    uint256[5] memory starters = userToTeam[user].defaultFive;

    for (uint256 i = 0; i < 5; i++) {
      uint24[10] memory stats = idToPlayer[starters[i]].stats;
      uint256 atk = stats[0] + stats[1] + stats[2] + stats[3] + stats[4];
      uint256 def = stats[5] + stats[6] + stats[7] + stats[8] + stats[9];

      if (i == 2) {
        // Joker player effects both fields' main scores
        unchecked {
          mainScore += atk + def * 1000000;
        }
      }

      if (i < 2) {
        // Attackers effect attack fields' main score and defence fields' secondary score
        mainScore += atk;

        unchecked {
          secondaryScore += def * 1000000;
        }

        continue;
      }

      // Defenders effect defence fields' main score and attack fields' secondary score
      secondaryScore += atk;
      unchecked {
          mainScore += def * 1000000;
      }
    }

    // x % 1e6 -> Attack score
    // x / 1e6 -> Defence score
    return (
      (6 * (mainScore % 1e6) + 3 * (secondaryScore % 1e6)) /
        160 +
        5000 *
        (6 - _uniqueAcademyCount(user)),
      (6 * (mainScore / 1e6) + 3 * (secondaryScore / 1e6)) /
        160 +
        5000 *
        (6 - _uniqueAcademyCount(user))
    );
  }

  // ############## PLAYER HELPERS ############## //

  /**
    @dev Feeds 0-99000 stat to f(x) = x**2/400_000 to get a number
    under the start cap which is 25_000
  */
  function _calculatePower(uint24 stat) private pure returns (uint24) {
    uint256 s = uint256(stat);
    return uint24(muldiv(s, s, 400_000));
  }

  /**
    @dev Returns a range of digits from a longer number
    @param num: Number to extract
    @param offset: Right side offset
    @param digits: Digits to extractr

    _modByDigit(12345, 1, 2) => ((12345 % 10**3) - (12345 % 10**1)) / 10**1
    => (345 - 5) / 10
    => 34
  */
  function _modByDigit(
    uint256 num,
    uint256 offset,
    uint256 digits
  ) private pure returns (uint24) {
    
    uint256 result = ((num % 10**(offset + digits)) - (num % 10**offset)) / 10**offset;
    return uint24(result);
  }

  /**
    @notice Checks the count of different academies one team has.
    @return count of different academies. E.g 5 means that each player is from a different academy
  */
  function _uniqueAcademyCount(address user) private view returns (uint32 count) {
    
    uint256[5] memory starters = userToTeam[user].defaultFive;

    // For each player
    for (uint256 i = 0; i < 5; i++) {
      bool exists = false;

      // Check the equivalence with previous players
      for (uint256 j = i; j > 0; j--) {
        if (
          idToPlayer[starters[i]].academyType == idToPlayer[starters[j - 1]].academyType
        ) {
          exists = true;
          break;
        }
      }

      if (!exists) {
          count++;
      }
    }
  }

  function _inDefaultFive(uint256 playerId) private view returns (bool) {
    
    uint256[5] memory starters = userToTeam[idToCoach[playerId]].defaultFive;

    for (uint256 i = 0; i < 5; i++) {
      if (starters[i] == playerId) return true;
    }
    return false;
  }

  /**
    @dev Remco Bloemen's muldiv function https://2π.com/21/muldiv/
    @dev Reasons why we use it:
      1. it is cheap on gas
      2. it doesn't revert where (a*b) overflows and (a*b)/c doesn't
  */
  function muldiv(
      uint256 a,
      uint256 b,
      uint256 denominator
  ) internal pure returns (uint256 result) {
    require(denominator > 0);

    uint256 prod0;
    uint256 prod1;
    assembly {
      let mm := mulmod(a, b, not(0))
      prod0 := mul(a, b)
      prod1 := sub(sub(mm, prod0), lt(mm, prod0))
    }

    if (prod1 == 0) {
      assembly {
          result := div(prod0, denominator)
      }
      return result;
    }
    require(prod1 < denominator);
    uint256 remainder;
    assembly {
      remainder := mulmod(a, b, denominator)
    }
    assembly {
      prod1 := sub(prod1, gt(remainder, prod0))
      prod0 := sub(prod0, remainder)
    }

    uint256 twos = denominator & (~denominator + 1);
    assembly {
      denominator := div(denominator, twos)
    }

    assembly {
      prod0 := div(prod0, twos)
    }

    assembly {
      twos := add(div(sub(0, twos), twos), 1)
    }
    prod0 |= prod1 * twos;

    uint256 inv = (3 * denominator) ^ 2;

    inv *= 2 - denominator * inv;
    inv *= 2 - denominator * inv;
    inv *= 2 - denominator * inv;
    inv *= 2 - denominator * inv;
    inv *= 2 - denominator * inv;
    inv *= 2 - denominator * inv;

    result = prod0 * inv;
    return result;
  }
}