pragma solidity ^0.4.15;

/**
 * Inspired by Lunyr.
 * Originally from https://github.com/TokenMarketNet/ico
 */

/**
 * Upgrade agent transfers tokens to a new contract.
 * Upgrade agent itself can be the token contract, or just a middle man contract doing the heavy lifting.
 *
 * The Upgrade agent is the interface used to implement a token
 * migration in the case of an emergency.
 * The function upgradeFrom has to implement the part of the creation
 * of new tokens on behalf of the user doing the upgrade.
 *
 * The new token can implement this interface directly, or use.
 */
contract UpgradeAgent {

  /** This value should be the same as the original token's total supply */
  uint public originalSupply;

  /** Interface to ensure the contract is correctly configured */
  function isUpgradeAgent() public constant returns (bool) {
    return true;
  }

  /**
  Upgrade an account

  When the token contract is in the upgrade status the each user will
  have to call `upgrade(value)` function from UpgradeableToken.

  The upgrade function adjust the balance of the user and the supply
  of the previous token and then call `upgradeFrom(value)`.

  The UpgradeAgent is the responsible to create the tokens for the user
  in the new contract.

  * @param from Account to upgrade.
  * @param value Tokens to upgrade.

  */
  function upgradeFrom(address from, uint value) public;

}
