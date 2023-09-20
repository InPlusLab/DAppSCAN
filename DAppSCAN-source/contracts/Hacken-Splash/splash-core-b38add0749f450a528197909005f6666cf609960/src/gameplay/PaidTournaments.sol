// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "oz-contracts/access/Ownable.sol";

// Token wrappers 
import "oz-contracts/token/ERC20/ERC20.sol";
import "oz-contracts/token/ERC721/ERC721.sol";
import "oz-contracts/token/ERC1155/ERC1155.sol";

import "./MatchMaker.sol";
import "../utils/Errors.sol";
import "../interfaces/IRegistry.sol";

enum Reward { ERC20, ERC721, ERC1155 }

struct TournamentDetails {
  Reward  rewardType;
  uint8   matchCount;
  address rewardAddress;
  uint256 rewardId;
  uint256 rewardAmount;
}

struct Tournament {
  bool   active;
  uint16 j;
  uint16 k;
  uint48 start;
  uint48 interval;
  TournamentDetails details;
}

struct TournamentRegistration {
  bool   active;
  uint8  cost;
  uint16 playerCount;
  uint16 tournamentCount;
  uint16 maxTournamentCount;
  uint48 entryDeadline;
  TournamentDetails details;
}

struct UserRegistration {
  bool registered;
}

/**
  @title Paid Tournament
  @notice Ticket based tournaments which can have ERC20/ERC721/ERC1155 prizes
  @author Hamza Karabag
*/
contract PaidTournaments is Ownable, MatchMaker {
  /* IRegistry registry from MatchMaker */

  uint48 constant TOURNAMENT_INTERVAL = 0 seconds;
  uint256 constant TIME_CAP = 4 weeks;

  uint128 private _tournamentTypeNonce;
  uint128 private _tournamentNonce;

  event NewTournament           (uint128 tournamentType);
  event TournamentRegistered    (address user, uint128 tournamentType);
  event TournamentFull          (uint128 tournamentType, uint16 tournamentIndex);
  event TournamentCreated       (uint128 tournamentId, uint128 tournamentType);
  event TournamentFinished      (uint128 tournamentId);

  mapping(uint128 => TournamentRegistration)      public  typeToRegistry;
  mapping(uint128 => Tournament)                  public  idToTournament;
  mapping(uint128 => mapping(uint16 => address))  public  tournamentToPlayers;
  mapping(uint128 => mapping(uint16 => address))  public  typeToQueue;
  mapping(address => UserRegistration)            private userToRegistry;

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

  // Register

  function startTournamentRegistration(
    TournamentDetails calldata details,
    uint8 cost,
    uint48 deadline, 
    uint16 maxTournamentCount
  ) external onlyCore {

    _tournamentTypeNonce++;
    TournamentRegistration storage tReg = typeToRegistry[_tournamentTypeNonce];
    
    require(!tReg.active, Errors.REG_STARTED);
    require(deadline > _now(), Errors.INVALID_DEADLINE);
    
    tReg.cost = cost;
    tReg.active = true;
    tReg.details = details;
    tReg.entryDeadline = deadline;
    tReg.maxTournamentCount = maxTournamentCount;

    Reward rewardType = details.rewardType;
    if(rewardType == Reward.ERC20) {
      require(IERC20(details.rewardAddress).transferFrom(
        msg.sender,
        address(this),
        details.rewardAmount
      ), "Token checkout failed");
    }
    else if(rewardType == Reward.ERC721) {
      IERC721(details.rewardAddress).safeTransferFrom(
        msg.sender,
        address(this),
        details.rewardId
      );
    }
    else if(rewardType == Reward.ERC1155) {
      IERC1155(details.rewardAddress).safeTransferFrom(
        msg.sender,
        address(this),
        details.rewardId,
        details.rewardAmount,
        ""
      );
    }

    emit NewTournament(_tournamentTypeNonce);
  }

  function register(uint128 tournamentType) external {

    TournamentRegistration storage tReg = typeToRegistry[tournamentType];

    require(tReg.active, Errors.REG_NOT_STARTED);
    require(tReg.tournamentCount < tReg.maxTournamentCount, Errors.TOURNAMENT_LIMIT);
    require(tReg.entryDeadline >= _now(), Errors.LATE_FOR_QUEUE);
    require(!userToRegistry[msg.sender].registered, Errors.ALREADY_REGISTERED);

    userToRegistry[msg.sender] = UserRegistration(true);
    typeToQueue[tournamentType][tReg.playerCount] = msg.sender;

    uint256 playerLimit = 2 ** tReg.details.matchCount;
    if(tReg.playerCount % playerLimit == playerLimit - 1) {
      emit TournamentFull(tournamentType, tReg.tournamentCount);
      tReg.tournamentCount++;
    }

    tReg.playerCount++;

    // Burn the tickets necessary to play
    registry.sp1155().burn(msg.sender, 11, tReg.cost);

    // This will revert if starters aren't ready
    registry.management().checkStarters(
      msg.sender, 
      tReg.details.matchCount, 
      tReg.entryDeadline + (tReg.details.matchCount * TOURNAMENT_INTERVAL)
    );
    registry.management().lockDefaultFive(msg.sender);
  }

  function requestTournamentRandomness() external onlyCore {
    registry.rng().requestBlockRandom(msg.sender);
  }

  function createTournament(uint128 tournamentType, uint16 tournamentIndex) external onlyCore {

    TournamentRegistration storage tReg = typeToRegistry[tournamentType];
    require(tReg.active, Errors.REG_NOT_STARTED);
    require(tReg.tournamentCount > 0, Errors.NO_TOURNAMENTS);

    uint16 playerLimit = uint16(2**tReg.details.matchCount);

    _tournamentNonce++;

    // Register the tournament
    idToTournament[_tournamentNonce] = Tournament({
      active:     true,
      j:          0,
      k:          playerLimit,
      start:      tReg.entryDeadline,
      interval:   TOURNAMENT_INTERVAL,
      details:    tReg.details
    });

    for (uint16 j = 0; j < 2**playerLimit; j++) {
      tournamentToPlayers[_tournamentNonce][j] = 
        typeToQueue[tournamentType][tournamentIndex * playerLimit + j];
    }

    emit TournamentCreated(_tournamentNonce, tournamentType);
  }

  function playTournamentRound(uint128 tournamentId) external onlyCore {

    Tournament memory tournament = idToTournament[tournamentId];
    require(_now() >= tournament.start, Errors.NEXT_MATCH_NOT_READY);

    registry.rng().checkBlockRandom(msg.sender);
    // Reverts if no random
    uint256 tournamentRandomness = registry.rng().getBlockRandom(msg.sender);

    uint256 remainingMatches = (tournament.k - tournament.j) / 2;
    // SWC-113-DoS with Failed Call: L211
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
            
      // Set next tour's player
      tournamentToPlayers[tournamentId][tournament.k] = tournamentToPlayers[tournamentId][
        tournament.j + gameOffset
      ];

      idToTournament[tournamentId].k += 1;
      idToTournament[tournamentId].j += 2;
    }

    // Use idToTournament[...]. to access mutated fields
    // Use tournament to access unchanged fields
    // TODO: gas golf
    if (idToTournament[tournamentId].k != (2**tournament.details.matchCount) * 2 - 1) {
      idToTournament[tournamentId].start += tournament.interval;
    } 
    else {
      emit TournamentFinished(tournamentId);
    }

    registry.rng().resetBlockRandom(msg.sender);
  }


  function getWinner(uint128 tournamentId) external view returns(address) {
    Tournament memory tournament = idToTournament[tournamentId];
    require(tournament.k == (2**tournament.details.matchCount) * 2 - 1, 
      Errors.TOURNAMENT_NOT_FINISHED);
  
    uint16 winnerIdx = uint16(2**tournament.details.matchCount) * 2 - 2;
    address first = tournamentToPlayers[tournamentId][winnerIdx];

    return first;
  }


  function finishTournament(uint128 tournamentId) external onlyCore {
    
    Tournament memory tournament = idToTournament[tournamentId];

    require(tournament.k == (2**tournament.details.matchCount) * 2 - 1, Errors.TOURNAMENT_NOT_FINISHED);

    uint16 winnerIdx = uint16(2**tournament.details.matchCount) * 2 - 2;
    address first = tournamentToPlayers[tournamentId][winnerIdx];

    address rewardAddress = tournament.details.rewardAddress;
    Reward rewardType = tournament.details.rewardType;

    // TODO: Change this to minting, tournaments are authorized contracts
    // anyway, there should be no difference instead of tokenomics implications
    if(rewardType == Reward.ERC20) {
      require(ERC20(rewardAddress).approve({
        spender: first, 
        amount: tournament.details.rewardAmount
      }), Errors.TOKEN_APPROVE_FAIL);
    }
    else if(rewardType == Reward.ERC721) {
      ERC721(rewardAddress).safeTransferFrom({
        from: address(this), 
        to: first, 
        tokenId: tournament.details.rewardId
      });
    }
    else if(rewardType == Reward.ERC1155) {
      ERC1155(rewardAddress).safeTransferFrom({
        from: address(this), 
        to: first, 
        id: tournament.details.rewardId, 
        amount: tournament.details.rewardAmount, 
        data: ""
      });
    }

    delete idToTournament[tournamentId].details;
    delete idToTournament[tournamentId];

    registry.management().unlockDefaultFive(first);
  }

  // Required so that we can receive ERC721s
  function onERC721Received(address,address,uint256,bytes memory) public virtual returns (bytes4) {
    return this.onERC721Received.selector;
  }

  // Required so that we can receive ERC1155s
  function onERC1155Received(address,address,uint256,uint256,bytes memory) public virtual returns (bytes4) {
    return this.onERC1155Received.selector;
  }

  function _now() private view returns(uint48) {
    return uint48(block.timestamp);
  }
}