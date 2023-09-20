// SWC-102-Outdated Compiler Version: L2-L96
/*
 * Blockchain Capital Token Smart Contract.  Copyright © 2017 by ABDK
 * Consulting.
 */
pragma solidity ^0.4.1;

import "./StandardToken.sol";

/**
 * Blockchain Capital Token Smart Contract.
 */
contract BCAPToken is StandardToken {
  /**
   * Create new Blockchain Capital Token contract with given central bank
   * address.
   *
   * @param _centralBank address of central bank
   */
  function BCAPToken (address _centralBank)
    StandardToken (_centralBank) {
    owner = _centralBank;
  }

  /**
   * Freeze token transfers.
   */
  function freezeTransfers () {
    if (msg.sender != owner) throw;

    if (!transfersFrozen) {
      transfersFrozen = true;
      Freeze ();
    }
  }

  /**
   * Unfreeze token transfers.
   */
  function unfreezeTransfers () {
    if (msg.sender != owner) throw;

    if (transfersFrozen) {
      transfersFrozen = false;
      Unfreeze ();
    }
  }

  /**
   * Transfer given number of tokens from message sender to given recipient.
   *
   * @param _to address to transfer tokens to the owner of
   * @param _value number of tokens to transfer to the owner of given address
   * @return true if tokens were transferred successfully, false otherwise
   */
  function transfer (address _to, uint256 _value) returns (bool success) {
    if (transfersFrozen) return false;
    else return AbstractToken.transfer (_to, _value);
  }

  /**
   * Transfer given number of tokens from given owner to given recipient.
   *
   * @param _from address to transfer tokens from the owner of
   * @param _to address to transfer tokens to the owner of
   * @param _value number of tokens to transfer from given owner to given
            recipient
   * @return true if tokens were transferred successfully, false otherwise
   */
  function transferFrom (address _from, address _to, uint256 _value)
  returns (bool success) {
    if (transfersFrozen) return false;
    else return AbstractToken.transferFrom (_from, _to, _value);
  }

  /**
   * Logged when transfers were frozen.
   */
  event Freeze ();

  /**
   * Logged when transfers were unfrozen.
   */
  event Unfreeze ();

  /**
   * Address of the owner of smart contract.  Only owner is allowed to
   * freeze/unfreeze transfers.
   */
  // SWC-135-Code With No Effects: L91 
  address owner;

  /**
   * Whether transfers are currently frozen or not.
   */
  bool transfersFrozen = false;
}
