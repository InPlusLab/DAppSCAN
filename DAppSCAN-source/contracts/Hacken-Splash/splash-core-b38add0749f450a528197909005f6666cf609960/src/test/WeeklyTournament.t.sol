// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "./helpers/Helpers.sol";
import "../utils/ABDKMath64x64.sol";

import {TournamentRegistration} 
  from "../gameplay/WeeklyTournaments.sol";

contract WeeklyTournamentTest is DSTest {
  using ABDKMath64x64 for int128;

  uint256 constant STARTING_BALANCE = 1000 * 10**18;

  uint256 constant PACK = 10;
  uint256 constant PACK_PRICE = 10 * 10**18;

  uint256 constant TICKET = 11;
  uint256 constant TICKET_PRICE = 10 * 10**18;

  uint256 constant BRONZE_STAKE = 100 * 10**18;
  uint48  constant BRONZE_TIME  = 10 days;

  uint256 constant SILVER_STAKE = 1000 * 10**18;
  uint48  constant SILVER_TIME  = 20 days;

  uint256 constant GOLD_STAKE   = 10000 * 10**18;
  uint48  constant GOLD_TIME    = 30 days;

  uint256 constant MONTHLY_REWARD     = 210_000 * 10**18;
  uint256 constant TOURNAMENT_REWARD  = 1000 * 10**18;
  uint256 constant REWARDS_PER_SECOND = MONTHLY_REWARD / 30 days;

  event TournamentFull(uint128 tournamentType, uint16 tournamentCount);
  event TournamentCreated(uint128 tournamentNonce, uint128 tournamentType);
  function setUp() public {
    AppStorage storage s = th.apps();
    s.cheats = CheatCodes(HEVM_ADDRESS);
    s.cheats.warp(1644132849);
  
    th.setAddresses();
    th.deployRegistry();
    th.deployMockRNG();
    th.deployManagement();
    th.deployTokens();
    
    // Transfer tokens to users
    s.cheats.startPrank(s.owner);
    s.sp20.transfer(s.alice, STARTING_BALANCE);
    s.sp20.transfer(s.bob, STARTING_BALANCE);
    s.sp20.transfer(s.claire, STARTING_BALANCE);
    s.sp20.transfer(s.dennis, STARTING_BALANCE);
    s.cheats.stopPrank();

    // Define staking conditions
    PassRequirement memory bronze = 
      PassRequirement(0,0,BRONZE_TIME,BRONZE_STAKE);
    PassRequirement memory silver = 
      PassRequirement(0,0,SILVER_TIME,SILVER_STAKE);
    PassRequirement memory gold = 
      PassRequirement(0,0,GOLD_TIME,GOLD_STAKE);

    PassRequirement[] memory reqs = new PassRequirement[](3);
    reqs[0] = bronze; reqs[1] = silver; reqs[2] = gold;

    th.deployStaking(REWARDS_PER_SECOND, reqs);
    th.deployWeeklyTournaments();
    th.deployMarketplace();

    // Set price for player packs
    s.cheats.prank(s.owner);
    s.markt.setCardPrice(PACK, PACK_PRICE);

    // Set price for tournament tickets
    s.cheats.prank(s.owner);
    s.markt.setCardPrice(TICKET, TICKET_PRICE);
  }

  function _buy_player(address to) private {
    AppStorage storage s = th.apps();
    s.cheats.startPrank(to);

    s.sp20.approve(address(s.markt), 2*TICKET_PRICE + PACK_PRICE);
    s.markt.buyCardFromSale(PACK, 1);
    s.markt.buyCardFromSale(TICKET, 2);
    
    s.cheats.stopPrank();
    assertEq(s.sp1155.balanceOf(to, PACK), 1);
    assertEq(s.sp1155.balanceOf(to, TICKET), 2);
    assertEq(s.sp20.balanceOf(to), 
      STARTING_BALANCE - 2*PACK_PRICE - TICKET_PRICE);
  }

  function _test_buy_players() private {
    AppStorage storage s = th.apps();

    _buy_player(s.alice);
    _buy_player(s.bob);
    _buy_player(s.claire);
    _buy_player(s.dennis);
  }

  function _open_pack(address to) private returns 
    (uint256[] memory players) {
    AppStorage storage s = th.apps();
    s.cheats.startPrank(to);
    
    s.management.registerTeam();
    s.management.requestOpenPackRandomness();
    players = s.management.openPack();
    
    s.cheats.stopPrank();
    assertEq(players.length, 5);
    assertEq(s.sp1155.balanceOf(to, PACK), 0);
  }

  function _test_prepare() private {
    _test_buy_players();

    AppStorage storage s = th.apps();
    s.alicePlayers  = _open_pack(s.alice);
    s.bobPlayers    = _open_pack(s.bob);
    s.clairePlayers = _open_pack(s.claire);
    s.dennisPlayers = _open_pack(s.dennis);
  }

  function _enter_stake(address who, uint256 amt, uint48 time) private {
    AppStorage storage s = th.apps();
    s.cheats.startPrank(who);
    s.sp20.approve(address(s.staking), amt);
    s.staking.enterStake(1, amt, time);
    s.cheats.stopPrank();

    int128 coeff = s.staking.getCoefficient(who);
    assertEq(coeff.toUInt(), 1);
    assertEq(s.staking.getPass(who), 1);
  }

  function _test_enter_stake() private {
    _test_prepare();

    AppStorage storage s = th.apps();
    s.cheats.prank(s.owner);
    s.sp20.transfer(address(s.staking), MONTHLY_REWARD);

    _enter_stake(s.alice, BRONZE_STAKE, BRONZE_TIME);
    _enter_stake(s.bob, BRONZE_STAKE, BRONZE_TIME);
    _enter_stake(s.claire, BRONZE_STAKE, BRONZE_TIME);
    _enter_stake(s.dennis, BRONZE_STAKE, BRONZE_TIME);
  }

  function _test_create_tournament() private {
    _test_enter_stake();
    
    AppStorage storage s = th.apps();
    s.cheats.startPrank(s.auth1);
    s.weekly.startTournamentRegistration(
      1, 
      uint48(block.timestamp + 2 hours), 
      2,
      TOURNAMENT_REWARD
    );
    s.cheats.stopPrank();
  }

  function _set_def_five(address who, uint256[] memory list) private {
    AppStorage storage s = th.apps();

    uint256[5] memory players;
    for (uint256 i = 0; i < 5; i++) {
      players[i] = list[i];
    }

    s.cheats.prank(who);
    s.management.setDefaultFive(players);
  }

  function _register(address who, uint256[] memory list) private {
    AppStorage storage s = th.apps();
    uint256[] memory emptyList;

    _set_def_five(who, list);
    s.cheats.prank(who);
    s.weekly.enterQueue(1, emptyList, emptyList);
  }

  function _test_enter_queue() private {
    _test_create_tournament();
    AppStorage storage s = th.apps();

    _register(s.alice, s.alicePlayers);
    _register(s.bob, s.bobPlayers);
    _register(s.claire, s.clairePlayers);
    _register(s.dennis, s.dennisPlayers);

    (,,uint16 playerCount,,,,) = s.weekly.passToRegistry(1);
    assertEq(playerCount, 4);
  }

  function _test_bob_leave_queue() private {
    _test_enter_queue();
    AppStorage storage s = th.apps();

    s.cheats.prank(s.bob);
    s.weekly.leaveQueue(1);

    assert(s.weekly.passToQueue(1,1) != address(0));
    assertEq(s.weekly.passToQueue(1,3), address(0));
  }

  function _test_start_tournament() private {
    _test_bob_leave_queue();
    AppStorage storage s = th.apps();
    _register(s.bob, s.bobPlayers);

    s.cheats.startPrank(s.auth1);

    s.weekly.createTournaments(1);
    
    s.cheats.stopPrank();
  }

  function test_play_tournament() public {
    _test_start_tournament();
    AppStorage storage s = th.apps();
    s.cheats.startPrank(s.auth1);

    s.cheats.warp(block.timestamp + 2 hours);
    s.weekly.requestTournamentRandomness();
    s.cheats.roll(block.number + 5);
    s.weekly.playTournamentRound(1);

    s.weekly.requestTournamentRandomness();
    s.cheats.roll(block.number + 5);
    s.weekly.playTournamentRound(1);

    (address first, address second) = s.weekly.getWinners(1);
    uint256 beforeFirst = s.sp20.balanceOf(first); 
    uint256 beforeSecond = s.sp20.balanceOf(second); 

    s.weekly.finishTournament(1);
    s.cheats.stopPrank();

    // Check all players are unlocked
    for (uint256 i = 0; i < 5; i++) {
      (bool lockedA,,,,,,) = s.management.idToPlayer(s.alicePlayers[i]);
      (bool lockedB,,,,,,) = s.management.idToPlayer(s.bobPlayers[i]);
      (bool lockedC,,,,,,) = s.management.idToPlayer(s.clairePlayers[i]);
      (bool lockedD,,,,,,) = s.management.idToPlayer(s.dennisPlayers[i]);
    
      assert(!lockedA && !lockedB && !lockedC && !lockedD);
    }

    uint256 deltaFirst = s.sp20.balanceOf(first) - beforeFirst;
    uint256 deltaSecond = s.sp20.balanceOf(second) - beforeSecond;

    assertEq(deltaFirst, 700 * 10**18);
    assertEq(deltaSecond, 300 * 10**18);
  }
}