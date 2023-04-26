// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../utils/Errors.sol";
import "../interfaces/IRegistry.sol";

abstract contract MatchMaker {
  IRegistry internal registry;

  uint256 constant UPGRADE_AMOUNT = 1000; // 1%

  constructor(IRegistry registryAddress) {
    registry = IRegistry(registryAddress);
  }

  /**
    @notice Runs a match between playerOne and playerTwo
    @param enableMorale:    When enabled morale is considered in calculations. False in tournaments
    @param playerOne:       Address of the first player
    @param playerTwo:       Address of the second player
    @param randomness:      Random number to calculate the result

    @dev returns 
    score:          Score of the playerOne, out of 7
    atkUpgrade:     Amount to upgrade playerOne's attack if they win
    defUpgrade:     Amount to upgrade playerOne's defence if they win

    @dev atkUpgrade and defUpgrade are propotional to the difference between points, where the relatively
    weaker team gets more points on win.
    @dev Emits MatchRound after each match to monitor 
  */
  function matchMaker(
      bool enableMorale,
      address playerOne,
      address playerTwo,
      uint256 randomness
  ) internal view returns (
    uint8 score,
    uint256 atkUpgrade,
    uint256 defUpgrade
  ) {
    Team memory teamOne = registry.management().getTeamOf(playerOne);
    require(teamOne.initialized, Errors.TEAM_NOT_INIT);

    (uint256 atkOne, uint256 defOne) = registry.management().getAtkAndDef(playerOne);
    (uint256 atkTwo, uint256 defTwo) = registry.management().getAtkAndDef(playerTwo);

    // Attack matches
    for (uint256 i = 0; i < 7; i++) {
      if (
        _lineWinner(
          muldiv((i < 4 ? atkOne : defOne), (enableMorale ? teamOne.morale : 100), 100),
          (i < 4 ? defTwo : atkTwo),
          randomness,
          i
        )) {
        score++;
      }
    }

    atkUpgrade = (UPGRADE_AMOUNT * atkOne) / (atkOne + atkTwo);
    defUpgrade = (UPGRADE_AMOUNT * defOne) / (defOne + defTwo);
  }

  function _lineWinner(
    uint256 ap,
    uint256 dp,
    uint256 randomness,
    uint256 round
  ) private pure returns (bool) {
    uint256 roundRandom = uint256(keccak256(abi.encodePacked(randomness, round)));
    return roundRandom % (muldiv(ap, 100, dp) + 100) >= 100;
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
  ) private pure returns (uint256 result) {
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
