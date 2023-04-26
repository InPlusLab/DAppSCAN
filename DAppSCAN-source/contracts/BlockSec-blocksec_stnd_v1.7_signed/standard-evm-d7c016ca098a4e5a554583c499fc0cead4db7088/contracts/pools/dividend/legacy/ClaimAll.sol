// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "../interfaces/IBondedStrategy.sol";


contract ClaimAll {
    address[] public allClaims;
    address public dividend;

    constructor(address dividend_) {
        dividend = dividend_;
    }

    function claimAll() external {
        uint256 len = allClaims.length;
        for (uint256 i = 0; i < len; ++i) {
            require(IBondedStrategy(dividend).claim(allClaims[i]), "ClaimAll: claim failed");
        }  
    } 

    function massClaim(address[] memory claims) external {
        uint256 len = claims.length;
        for (uint256 i = 0; i < len; ++i) {
            require(IBondedStrategy(dividend).claim(claims[i]), "ClaimAll: claim failed");
        }  
    }

    function addClaim(address claim) external {
        allClaims.push(claim);
    }
}