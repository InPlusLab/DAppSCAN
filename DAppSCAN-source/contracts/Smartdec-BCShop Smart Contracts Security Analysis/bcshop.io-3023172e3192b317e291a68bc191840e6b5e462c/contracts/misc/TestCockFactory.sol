pragma solidity ^0.4.10;

import "../cocks/CockFactory.sol";

contract TestCockFactory is CockFactory {
    // function TestCockFactory(
    //     ICockStorage _cockStorage, 
    //     IERC20Token _token, 
    //     Random _rng, 
    //     uint32 _healthRngMax,
    //     uint32 _musclesRngMax,
    //     uint32 _fatRngMax,
    //     uint32 _healthMultiplier,
    //     uint32 _musclesMultiplier,
    //     uint32 _fatMultiplier,
    //     uint16 _minMatches,
    //     uint16 _maxMatches
    // ) 
    // CockFactory(
    //     _cockStorage, 
    //     _token, 
    //     _rng, 
    //     _healthRngMax,
    //     _musclesRngMax,
    //     _fatRngMax,
    //     _healthMultiplier,
    //     _musclesMultiplier,
    //     _fatMultiplier,
    //     _minMatches,
    //     _maxMatches
    // )     
    //     public
    // {        
    // }

    // function createCustomCock(uint32 health, uint32 muscles, uint32 fat, address owner, uint256 tokenInvested)  ownerOnly {
    //     cockStorage.addCock(
    //         health, 
    //         muscles,
    //         fat,
    //         owner, 
    //         tokenInvested);
    // }

    // function getFightResultExtended(uint256 cock1, uint256 cock2) public constant returns(uint8, uint256, uint256) {
    //     var (health1, muscles1, fat1) = cockStorage.getCockParams(cock1);
    //     var (health2, muscles2, fat2) = cockStorage.getCockParams(cock2);
        
    //     uint256 effectiveHp2 = health2 * fat2 / (muscles1 * fat1); //ehp2 = health2 / dmg1
    //     uint256 effectiveHp1 = health1 * fat1 / (muscles2 * fat2);  //ehp1 = health1 / dmg2

    //     uint8 result = effectiveHp1 > effectiveHp2 ? 1 :
    //            effectiveHp1 == effectiveHp2 ? 0 :
    //                                          2;
    //     return (result, effectiveHp1, effectiveHp2);
    // }
}