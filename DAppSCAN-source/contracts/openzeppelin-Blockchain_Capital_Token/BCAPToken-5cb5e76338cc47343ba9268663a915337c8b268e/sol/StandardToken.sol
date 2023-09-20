/*
 * Standard Token Smart Contract.  Copyright © 2016 by ABDK Consulting.
 */
pragma solidity ^0.4.1;

import "./AbstractToken.sol";

/**
 * Standard Token Smart Contract that implements ERC-20 token with special
 * unlimited supply "Central Bank" account.
 */
contract StandardToken is AbstractToken {
  uint256 constant private MAX_UINT256 =
    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

  /**
   * Create new Standard Token contract with given "Central Bank" account.
   *
   * @param _centralBank address of "Central Bank" account
   */
  function StandardToken (address _centralBank) AbstractToken () {
    centralBank = _centralBank;
    accounts [_centralBank] = MAX_UINT256;
  }

  /**
   * Get total number of tokens in circulation.
   *
   * @return total number of tokens in circulation
   */
  function totalSupply () constant returns (uint256 supply) {
    return safeSub (MAX_UINT256, accounts [centralBank]);
  }

  /**
   * Get number of tokens currently belonging to given owner.
   *
   * @param _owner address to get number of tokens currently belonging to the
            owner of
   * @return number of tokens currently belonging to the owner of given address
   */
  function balanceOf (address _owner) constant returns (uint256 balance) {
    return _owner == centralBank ? 0 : AbstractToken.balanceOf (_owner);
  }

  /**
   * Address of "Central Bank" account.
   */
  address private centralBank;
}
