pragma solidity ^0.4.15;

/**
 * Originally from https://github.com/TokenMarketNet/ico
 * Modified by https://www.coinfabrik.com/
 */

import "./StandardToken.sol";
import "./Ownable.sol";

/**
 * Define interface for releasing the token transfer after a successful crowdsale.
 */
contract ReleasableToken is StandardToken, Ownable {

  /* The finalizer contract that allows lifting the transfer limits on this token */
  address public releaseAgent;

  /** A crowdsale contract can release us to the wild if ICO success. If false we are are in transfer lock up period.*/
  bool public released = false;

  /** Map of agents that are allowed to transfer tokens regardless of the lock down period. These are crowdsale contracts and possible the team multisig itself. */
  mapping (address => bool) public transferAgents;

  /**
   * Set the contract that can call release and make the token transferable.
   *
   * Since the owner of this contract is (or should be) the crowdsale,
   * it can only be called by a corresponding exposed API in the crowdsale contract in case of input error.
   */
  function setReleaseAgent(address addr) onlyOwner inReleaseState(false) public {
    // We don't do interface check here as we might want to have a normal wallet address to act as a release agent.
    releaseAgent = addr;
  }

  /**
   * Owner can allow a particular address (e.g. a crowdsale contract) to transfer tokens despite the lock up period.
   */
  function setTransferAgent(address addr, bool state) onlyOwner inReleaseState(false) public {
    transferAgents[addr] = state;
  }

  /**
   * One way function to release the tokens into the wild.
   *
   * Can be called only from the release agent that should typically be the finalize agent ICO contract.
   * In the scope of the crowdsale, it is only called if the crowdsale has been a success (first milestone reached).
   */
  function releaseTokenTransfer() public onlyReleaseAgent {
    released = true;
  }

  /**
   * Limit token transfer until the crowdsale is over.
   */
  modifier canTransfer(address sender) {
    require(released || transferAgents[sender]);
    _;
  }

  /** The function can be called only before or after the tokens have been released */
  modifier inReleaseState(bool releaseState) {
    require(releaseState == released);
    _;
  }

  /** The function can be called only by a whitelisted release agent. */
  modifier onlyReleaseAgent() {
    require(msg.sender == releaseAgent);
    _;
  }

  /** We restrict transfer by overriding it */
  function transfer(address to, uint value) public canTransfer(msg.sender) returns (bool success) {
    // Call StandardToken.transfer()
   return super.transfer(to, value);
  }

  /** We restrict transferFrom by overriding it */
  function transferFrom(address from, address to, uint value) public canTransfer(from) returns (bool success) {
    // Call StandardToken.transferForm()
    return super.transferFrom(from, to, value);
  }

}


