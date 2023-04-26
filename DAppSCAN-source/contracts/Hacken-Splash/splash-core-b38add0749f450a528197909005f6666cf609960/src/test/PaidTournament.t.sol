// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "./helpers/Helpers.sol";
import "../utils/ABDKMath64x64.sol";

import {TournamentDetails, TournamentRegistration, Reward} 
  from "../gameplay/PaidTournaments.sol";

contract PaidTournamentTest is DSTest {
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
    th.deployPaidTournaments();
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

  function test_buy_players() public {
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

  function test_prepare() public {
    test_buy_players();

    AppStorage storage s = th.apps();
    s.alicePlayers  = _open_pack(s.alice);
    s.bobPlayers    = _open_pack(s.bob);
    s.clairePlayers = _open_pack(s.claire);
    s.dennisPlayers = _open_pack(s.dennis);
  }

  // function _enter_stake(address who, uint256 amt, uint48 time) private {
  //   AppStorage storage s = th.apps();
  //   s.cheats.startPrank(who);
  //   s.sp20.approve(address(s.staking), amt);
  //   s.staking.enterStake(1, amt, time);
  //   s.cheats.stopPrank();

  //   int128 coeff = s.staking.getCoefficient(who);
  //   assertEq(coeff.toUInt(), 1);
  // }

  // function test_enter_stake() public {
  //   test_prepare();

  //   AppStorage storage s = th.apps();
  //   s.cheats.prank(s.owner);
  //   s.sp20.transfer(address(s.staking), MONTHLY_REWARD);

  //   _enter_stake(s.alice, BRONZE_STAKE, BRONZE_TIME);
  //   _enter_stake(s.bob, BRONZE_STAKE, BRONZE_TIME);
  //   _enter_stake(s.claire, BRONZE_STAKE, BRONZE_TIME);
  //   _enter_stake(s.dennis, BRONZE_STAKE, BRONZE_TIME);
  // }

  function test_start_tournament() public {
    test_prepare();

    AppStorage storage s = th.apps();
    s.cheats.prank(s.owner);
    s.sp20.transfer(s.auth1, STARTING_BALANCE);
    s.cheats.startPrank(s.auth1);
    
    s.sp20.approve(address(s.paid), STARTING_BALANCE);

    TournamentDetails memory details = TournamentDetails(
      Reward.ERC20, 2, address(s.sp20), 0, STARTING_BALANCE
    );

    s.paid.startTournamentRegistration(
      details, 1, uint48(block.timestamp + 2 hours), 1);

    s.cheats.stopPrank();

    assertEq(s.sp20.balanceOf(s.auth1), 0);

    (bool active,,,,,, ) = s.paid.typeToRegistry(1);
    assert(active);
  }

  function test_enter_tournament_fail() public {
    test_start_tournament();

    AppStorage storage s = th.apps();
    s.cheats.startPrank(s.alice);

    s.cheats.expectRevert(bytes(""));
    s.paid.register(1);
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

  function _register(address who) private {
    AppStorage storage s = th.apps();
    
    s.cheats.prank(who);
    s.paid.register(1);
  }

  function test_enter_tournament() public {
    test_start_tournament();
    AppStorage storage s = th.apps();

    _set_def_five(s.alice, s.alicePlayers);
    _register(s.alice);

    _set_def_five(s.bob, s.bobPlayers);
    _register(s.bob);

    _set_def_five(s.claire, s.clairePlayers);
    _register(s.claire);

    _set_def_five(s.dennis, s.dennisPlayers);
    
    s.cheats.expectEmit(false, false, false, true);
    emit TournamentFull(1,0);
    s.cheats.prank(s.dennis);
    s.paid.register(1);
  }

  function test_play_tournament_fail() public {
    test_enter_tournament();
    AppStorage storage s = th.apps();
    s.cheats.prank(s.auth1);
    s.paid.createTournament(1, 0);
   
    s.cheats.prank(s.auth1);
    s.cheats.expectRevert(bytes("Next match is not ready"));
    s.paid.playTournamentRound(1);
  }

  function test_play_tournament() public {
    test_enter_tournament();
    AppStorage storage s = th.apps();
    s.cheats.startPrank(s.auth1);
    s.cheats.expectEmit(false, false, false, true);
    emit TournamentCreated(1, 1);
    s.paid.createTournament(1, 0);

    s.cheats.warp(block.timestamp + 2 hours);

    // Play semi finals
    s.cheats.roll(block.number + 5);
    s.paid.requestTournamentRandomness();
    s.cheats.roll(block.number + 1);

    s.paid.playTournamentRound(1);

    // Play finals
    s.paid.requestTournamentRandomness();
    s.cheats.roll(block.number + 1);
    s.paid.playTournamentRound(1);

    // It's Claire
    address winner = s.paid.getWinner(1);

    s.paid.finishTournament(1);
    s.cheats.stopPrank();

    assertEq(s.sp20.allowance(address(s.paid), winner), STARTING_BALANCE);
  }


}