// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "./helpers/Helpers.sol";

contract PlayerTest is DSTest {

    event PlayerMinted(uint256 indexed playerId);
    event Random(uint256 indexed playerId);

    function setUp() public {
        AppStorage storage s = th.apps();
        s.cheats = CheatCodes(HEVM_ADDRESS);
        s.cheats.warp(1644132849);

        th.setAddresses();
        th.deployRegistry();
        th.deployMockRNG();
        th.deployManagement();
        th.deployTokens();
    }

    function test_mint_player_cards() public {
        AppStorage storage s = th.apps();
        
        s.cheats.prank(s.owner);
        s.sp1155.mint(s.alice, 10, 1, "");
        
        s.cheats.prank(s.owner);
        s.sp1155.mint(s.bob, 10, 1, "");

        assertEq(s.sp1155.balanceOf(s.alice, 10), 1);
    }

    function test_open_player_packs() public {
        test_mint_player_cards();

        AppStorage storage s = th.apps();

        s.cheats.startPrank(s.alice);

        s.management.registerTeam();
        s.management.requestOpenPackRandomness();

        s.cheats.record();
        uint256[] memory players = s.management.openPack();

        assertEq(players.length, 5);
    }
}
