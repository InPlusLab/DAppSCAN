/**
 * COPYRIGHT © 2020 RARI CAPITAL, INC. ALL RIGHTS RESERVED.
 * Anyone is free to integrate the public APIs (described in `API.md` of the `rari-contracts` package) of the official smart contract instances deployed by Rari Capital, Inc. in any application (commercial or noncommercial and under any license) benefitting Rari Capital, Inc.
 * Only those with explicit permission from a co-founder of Rari Capital (Jai Bhavnani, Jack Lipstone, or David Lucid) are permitted to study, review, or analyze any part of the source code contained in the `rari-contracts` package.
 * Reuse (including deployment of smart contracts other than private testing on a private network), modification, redistribution, or sublicensing of any source code contained in the `rari-contracts` package is not permitted without the explicit permission of David Lucid of Rari Capital, Inc.
 * No one is permitted to use the software for any purpose other than those allowed by this license.
 * This license is liable to change at any time at the sole discretion of David Lucid of Rari Capital, Inc.
 */

pragma solidity ^0.5.7;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";

/**
 * @title RariGovernanceToken
 * @author David Lucid <david@rari.capital> (https://github.com/davidlucid)
 * @notice RariGovernanceToken is the ERC20 token contract accounting for the ownership of RariFund.
 */
contract RariGovernanceToken is ERC20, ERC20Detailed {
    using SafeMath for uint256;

    /**
     * @dev Constructor for RariGovernanceToken.
     */
    constructor () public ERC20Detailed("Rari Governance Token", "RGT", 18) {
        _mint(msg.sender, 10e6 * (10 ** uint256(decimals())));
    }
}
