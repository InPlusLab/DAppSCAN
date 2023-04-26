// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "oz-contracts/access/Ownable.sol";

import "./MatchMaker.sol";
import "../utils/ABDKMath64x64.sol";
import "../utils/Errors.sol";
import "../interfaces/IRegistry.sol";

struct Tournament {
  uint8 matchCount;
  uint16 j;
  uint16 k;
  uint48 start;
  uint48 interval;
  uint256 prizePool;
}

struct TournamentRegistration {
  bool active;
  uint8 matchCount;
  uint16 playerCount;
  uint48 deadline;
  uint64 tournamentCount;
  uint128 lastId;
  uint256 prizePool;
}

struct UserRegistry {
  bool registered;
  uint16 registeredIdx;
  uint256[] veterans;
  uint256[] retireds;
}

/**
  @title WeeklyTournaments

  @author Hamza Karabag
*/
contract WeeklyTournaments is Ownable, MatchMaker {
  using ABDKMath64x64 for int128;
  /* IRegistry registry from MatchMaker */

  uint48 constant TOURNAMENT_INTERVAL = 0 seconds;

  uint8   private _firstWeight = 7;
  uint8   private _secondWeight = 3;
  uint128 private _tournamentNonce;

  event TournamentRegistered    (address user, uint8 pass);
  event TournamentCreated       (uint128 tournamentId, uint8 pass);
  event TournamentFinished      (uint128 tournamentId);
  event FirstWeightChanged      (uint8 newWeight);
  event SecondWeightChanged     (uint8 newWeight);

  mapping(uint128 => Tournament)                  public idToTournament;
  mapping(uint128 => mapping(uint16 => address))  public tournamentToPlayers;
  mapping(uint8 => TournamentRegistration)        public passToRegistry;
  mapping(uint8 => mapping(uint16 => address))    public passToQueue;
  mapping(address => UserRegistry)                private userToRegistry;

  modifier onlyCore() {
    require(registry.core(msg.sender), Errors.NOT_CORE);
    _;
  }

  modifier checkStarters() {
    // This will revert if starters are not ready
    registry.management().checkStarters(msg.sender);
    _;
  }

  constructor(IRegistry registryAddress) MatchMaker(registryAddress) { }

  // ############## SETTERS ############## //

  function setFirstWeight(uint8 newWeight) external onlyOwner {
    _firstWeight = newWeight;
    emit FirstWeightChanged(newWeight);
  }

  function setSecondWeight(uint8 newWeight) external onlyOwner {
    _secondWeight = newWeight;
    emit SecondWeightChanged(newWeight);

  }

  // ############## TOURNAMENT CREATION ############## //
  
  /**
    == ONLY CORE ==

    @notice Starts tournament registration for a certain pass
    @param pass _
    @param deadline timestamp until when users can register
    @param matchCount of tournament
    @param prizePool of tournament
  */
  function startTournamentRegistration( 
    uint8 pass, 
    uint48 deadline, 
    uint8 matchCount, 
    uint256 prizePool
  ) external onlyCore {

    TournamentRegistration storage tReg = passToRegistry[pass];
    
    require(!tReg.active, Errors.REG_STARTED);
    require(deadline > _now(), Errors.INVALID_DEADLINE);
    
    tReg.active = true;
    tReg.deadline = deadline;
    tReg.matchCount = matchCount;
    tReg.prizePool = prizePool;
  }


  /**
    @notice Enters the queue for a tournament
    @param pass Each tournament has a pass, indicating some of its props

    @dev Management contract checks msg.sender's players to ensure they are eligible
  */
  function enterQueue(
    uint8 pass, 
    uint256[] memory veteranList,
    uint256[] memory retiredList
  ) external checkStarters {
    TournamentRegistration storage tReg = passToRegistry[pass];

    require(tReg.active, Errors.REG_NOT_STARTED);
    require(!userToRegistry[msg.sender].registered, Errors.ALREADY_REGISTERED);
    require(pass != 0, Errors.INVALID_PASS);
    require(_now() <= tReg.deadline, Errors.LATE_FOR_QUEUE);

    uint8 currentPass = registry.staking().getPass(msg.sender);
    require(pass == currentPass, Errors.NOT_RIGHT_PASS);

    PassRequirement memory requirements = registry.staking().getPassRequirements(pass);
    require(
      veteranList.length == requirements.veteranCount && 
      retiredList.length == requirements.retiredCount, 
      Errors.NOT_ENOUGH_PLAYERS_STAKED
    );

    userToRegistry[msg.sender] = UserRegistry(
      true, 
      tReg.playerCount, 
      veteranList, 
      retiredList
    );

    passToQueue[pass][tReg.playerCount++] = msg.sender;

    uint256 playerLimit = 2 ** tReg.matchCount;
    if(tReg.playerCount % playerLimit == playerLimit - 1) {
      tReg.tournamentCount++;
    }

    IManagement management = registry.management();
    // These will revert if there's a problem with locking
    management.lockVeteranBatch(msg.sender, veteranList);
    management.lockRetiredBatch(msg.sender, retiredList);

    // This will also revert if starters aren't ready
    management.checkStarters(
      msg.sender, 
      tReg.matchCount, 
      tReg.deadline + (tReg.matchCount * TOURNAMENT_INTERVAL)
    );
    management.lockDefaultFive(msg.sender);

    emit TournamentRegistered(msg.sender, pass);
  }


  function leaveQueue(uint8 pass) external {
    
    TournamentRegistration memory tReg = passToRegistry[pass];
    UserRegistry memory uReg = userToRegistry[msg.sender];
    
    require(tReg.playerCount > 0, Errors.TOURNAMENT_EMPTY);
    require(
      passToQueue[pass][uReg.registeredIdx] == msg.sender, 
      Errors.NOT_IN_TOURNAMENT
    );

    passToRegistry[pass].playerCount -= 1;

    if(tReg.playerCount > 1) {
      passToQueue[pass][uReg.registeredIdx] = 
        passToQueue[pass][tReg.playerCount-1];
    }

    delete passToQueue[pass][tReg.playerCount-1];
    delete userToRegistry[msg.sender];

    IManagement management = registry.management();
    management.unlockDefaultFive(msg.sender);
    management.unlockVeteranBatch(msg.sender, uReg.veterans);
    management.unlockRetiredBatch(msg.sender, uReg.retireds);
  }
  
  /**
    == ONLY CORE ==

    @dev Sets a checkpoint for the RNG algorithm we use
  */
  function requestTournamentRandomness() external onlyCore {
    registry.rng().requestBlockRandom(msg.sender);
  }


  /**
    == ONLY CORE ==

    @notice Creates tournaments after registration
    @param pass Each tournament has a pass, indicating some of its props
    @dev Core user can create tournaments before the deadline is finished
  */
  function createTournaments(uint8 pass) external onlyCore {

    TournamentRegistration storage tReg = passToRegistry[pass];
    require(tReg.active, Errors.REG_NOT_STARTED);
    require(tReg.tournamentCount > 0, Errors.NO_TOURNAMENTS);

    tReg.active = false;

    // Divide the player pool into individual tournaments
    uint256 tournamentCount = tReg.tournamentCount;
    uint16 playerLimit = uint16(2**tReg.matchCount);
    for (uint128 i = 0; i < tournamentCount; i++) {
      _tournamentNonce++;

      // Register the tournament
      idToTournament[_tournamentNonce] = Tournament({
        matchCount: tReg.matchCount,
        j: 0,
        k: playerLimit,
        start: tReg.deadline,
        interval: TOURNAMENT_INTERVAL,
        prizePool: tReg.prizePool / tournamentCount
      });

      for (uint16 j = 0; j < playerLimit; j++) {
        tournamentToPlayers[_tournamentNonce][j] = 
          passToQueue[pass][uint16(i*playerLimit + j)];
      }

      emit TournamentCreated(_tournamentNonce, pass);      
    }
  }


  /**
    == ONLY CORE ==

    @notice Plays a single round of a tournament
    @param tournamentId Each tournament has an ID

  */
  function playTournamentRound(uint128 tournamentId) external onlyCore {

    Tournament memory tournament = idToTournament[tournamentId];
    
    require(_now() >= tournament.start, Errors.NEXT_MATCH_NOT_READY);

    // Requires a new request for random
    registry.rng().checkBlockRandom(msg.sender);
    uint256 tournamentRandomness = registry.rng().getBlockRandom(msg.sender);

    uint256 remainingMatches = (tournament.k - tournament.j) / 2;

    for (uint256 i = 0; i < remainingMatches; i++) {
      tournament = idToTournament[tournamentId];

      (uint8 score, , ) = matchMaker({
        enableMorale: false,
        playerOne: tournamentToPlayers[tournamentId][tournament.j],
        playerTwo: tournamentToPlayers[tournamentId][tournament.j + 1],
        randomness: tournamentRandomness
      });

      uint8 gameOffset = score >= 4 ? 1 : 0;

      registry.management().afterTournamentRound({
        userOne: tournamentToPlayers[tournamentId][tournament.j],
        userTwo: tournamentToPlayers[tournamentId][tournament.j + 1]
      });
            
      // Set next round's player
      tournamentToPlayers[tournamentId][tournament.k] = tournamentToPlayers[tournamentId][
        tournament.j + gameOffset
      ];

      address loser = tournamentToPlayers[tournamentId][tournament.j + (1 ^ gameOffset)]; 
      // Unlock the losing player's default five

      // TODO: Group these into one call
      IManagement management = registry.management();
      management.unlockDefaultFive(loser);
      management.unlockVeteranBatch(loser, userToRegistry[loser].veterans);
      management.unlockRetiredBatch(loser, userToRegistry[loser].retireds);

      idToTournament[tournamentId].k += 1;
      idToTournament[tournamentId].j += 2;
    }

    // Use idToTournament[...]. to access mutated fields
    // Use tournament to access unchanged fields
    // TODO: gas golf
    if (idToTournament[tournamentId].k != (2**tournament.matchCount) * 2 - 1) {
      idToTournament[tournamentId].start += tournament.interval;
    } 
    else {
      emit TournamentFinished(tournamentId);
    }

    registry.rng().resetBlockRandom(msg.sender);
  }

  function getWinners(uint128 tournamentId) public view returns(address, address) {
    Tournament memory tournament = idToTournament[tournamentId];
    uint16 playerCount = uint16(2**tournament.matchCount);

    require(
      tournament.k == playerCount * 2 - 1, 
      Errors.TOURNAMENT_NOT_FINISHED
    );
  
    uint16 winnerIdx = playerCount * 2 - 2;
    address first = tournamentToPlayers[tournamentId][winnerIdx];
    address second = tournamentToPlayers[tournamentId][winnerIdx-1] != first
      ? tournamentToPlayers[tournamentId][winnerIdx-1]
      : tournamentToPlayers[tournamentId][winnerIdx-2];

    return ( first, second );
  }

  /**
    == ONLY CORE ==

    @notice Ends a tournament
    @param tournamentId _

    @dev Winner prize is calculating using 
      Prize = TotalPrize * m*A / (m*A + n*B) where:
      m: Prize weight of 1st place
      n: Prize weight of 2nd place
      A: Stake coefficient of 1st user
      B: Stake coefficeient of 2nd user

    @dev Second prize is basically (Total prize - Winner prize)
  */
  function finishTournament(uint128 tournamentId) external onlyCore {
    Tournament memory tournament = idToTournament[tournamentId];

    (address first, address second) = getWinners(tournamentId);
    uint256 totalPrize = tournament.prizePool;

    int128 firstCoeff = registry.staking().getCoefficient(first);
    int128 secondCoeff = registry.staking().getCoefficient(second);

    uint256 winnerPrize = (firstCoeff.mulu(_firstWeight) * totalPrize) / 
      (firstCoeff.mulu(_firstWeight) + secondCoeff.mulu(_secondWeight));

    assert(winnerPrize < totalPrize);

    IManagement management = registry.management();
    management.unlockDefaultFive(first);
    management.unlockVeteranBatch(first, userToRegistry[first].veterans);
    management.unlockRetiredBatch(first, userToRegistry[first].retireds);

    // Approve prize to the winner
    ISP20 sp20 = registry.sp20();
    sp20.mint(first, winnerPrize);
    sp20.mint(second, totalPrize - winnerPrize);
  }

  function _now() private view returns(uint48) {
    return uint48(block.timestamp);
  }
}