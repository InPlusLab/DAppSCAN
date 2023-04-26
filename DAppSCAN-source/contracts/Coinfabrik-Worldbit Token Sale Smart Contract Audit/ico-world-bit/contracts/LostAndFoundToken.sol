pragma solidity ^0.4.15;

/**
 * Authored by https://www.coinfabrik.com/
 */

import "./EIP20Token.sol";

// This contract aims to provide an inheritable way to recover tokens from a contract not meant to hold tokens
// To use this contract, have your token-ignoring contract inherit this one and implement getLostAndFoundMaster to decide who can move lost tokens.
// Of course, this contract imposes support costs upon whoever is the lost and found master.
contract LostAndFoundToken {
  /**
   * @return Address of the account that handles movements.
   */
  function getLostAndFoundMaster() internal constant returns (address);

  /**
   * @param agent Address that will be able to move tokens with transferFrom
   * @param tokens Amount of tokens approved for transfer
   * @param token_contract Contract of the token
   */
  function enableLostAndFound(address agent, uint tokens, EIP20Token token_contract) public {
    require(msg.sender == getLostAndFoundMaster());
    // We use approve instead of transfer to minimize the possibility of the lost and found master
    //  getting them stuck in another address by accident.
    token_contract.approve(agent, tokens);
  }
}