// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./CheatCodes.sol";

import "../../mock/MockRNG.sol";
import "../../mock/MockManagement.sol";

import "../../tokens/SP721.sol";
import "../../tokens/SP1155.sol";
import "../../tokens/SP20.sol";
import "../../staking/Staking.sol";
import "../../registry/Registry.sol";
import "../../marketplace/Marketplace.sol";
import "../../gameplay/TrainingMatches.sol";

import { PaidTournaments } from "../../gameplay/PaidTournaments.sol";
import { WeeklyTournaments } from "../../gameplay/WeeklyTournaments.sol";

struct AppStorage {
  CheatCodes cheats;
  /* Contracts  */
  SPLASH sp20;
  PLAYER sp721;
  CARDS sp1155;
  MockRNG rng;
  Staking staking;
  Registry registry;
  Marketplace markt;
  PaidTournaments paid;
  MockManagement management;
  WeeklyTournaments weekly;
  /* Addresses */
  address owner;
  address auth1;
  address auth2;
  address alice;
  address bob;
  address claire;
  address dennis;
  uint256[] alicePlayers;
  uint256[] bobPlayers;
  uint256[] clairePlayers;
  uint256[] dennisPlayers;
}

// Test Helpers
library th {
  function apps() public pure returns (AppStorage storage appStorage) {
    bytes32 appSlot = keccak256(abi.encodePacked("appSlot"));
    assembly { appStorage.slot := appSlot }
  }

  function setAddresses() external {
    AppStorage storage s = apps();

    s.owner   = s.cheats.addr(10);
    s.auth1   = s.cheats.addr(20);
    s.auth2   = s.cheats.addr(30);
    s.alice   = s.cheats.addr(40);
    s.bob     = s.cheats.addr(50);
    s.claire  = s.cheats.addr(60);
    s.dennis  = s.cheats.addr(70);
  }

  function deployRegistry() external {
    AppStorage storage s = apps();
    s.cheats.startPrank(s.owner);

    s.registry = new Registry();
    s.registry.giveCoreAccess(s.auth1);
    s.registry.giveAuthorization(s.auth1);
    s.registry.giveCoreAccess(s.auth2);

    s.cheats.stopPrank();
  }

  function deployMockRNG() external {
    AppStorage storage s = apps();
    s.cheats.startPrank(s.owner);

    s.rng = new MockRNG(s.registry);
    s.registry.setRng(s.rng);

    s.cheats.stopPrank();
  }

  function deployManagement() external {
    AppStorage storage s = apps();
    s.cheats.startPrank(s.owner);
    
    s.management = new MockManagement(s.registry);
    s.registry.setManagement(s.management);
    
    s.cheats.stopPrank();
  }

  function deployMarketplace() external {
    AppStorage storage s = apps();
    s.cheats.startPrank(s.owner);

    s.markt = new Marketplace(s.registry);
    s.registry.giveAuthorization(address(s.markt));

    s.cheats.stopPrank();
  }

  function deployTokens() external {
    AppStorage storage s = apps();
    s.cheats.startPrank(s.owner);

    s.sp20    = new SPLASH(s.registry);
    s.sp721   = new PLAYER(s.registry);
    s.sp1155  = new CARDS(s.registry);

    s.registry.setSp20(s.sp20);
    s.registry.setSp721(s.sp721);
    s.registry.setSp1155(s.sp1155);

    s.sp20.mint(s.owner, 100000 * 10**18);
    s.sp1155.setApprovalForAll(address(s.management), true);
    
    s.cheats.stopPrank();
  }

  function deployStaking(uint256 rewardPerSecond, PassRequirement[] memory reqs) external{
    AppStorage storage s = apps();
    s.cheats.startPrank(s.owner);

    s.staking = new Staking(s.registry, rewardPerSecond, reqs);
    s.registry.setStaking(s.staking);

    s.cheats.stopPrank();    
  }

  function deployPaidTournaments() external {
    AppStorage storage s = apps();
    s.cheats.startPrank(s.owner);

    s.paid = new PaidTournaments(s.registry);
    s.registry.giveAuthorization(address(s.paid));

    s.cheats.stopPrank();
  }

  function deployWeeklyTournaments() external {
    AppStorage storage s = apps();
    s.cheats.startPrank(s.owner);

    s.weekly = new WeeklyTournaments(s.registry);
    s.registry.giveAuthorization(address(s.weekly));

    s.cheats.stopPrank();
  }
}
