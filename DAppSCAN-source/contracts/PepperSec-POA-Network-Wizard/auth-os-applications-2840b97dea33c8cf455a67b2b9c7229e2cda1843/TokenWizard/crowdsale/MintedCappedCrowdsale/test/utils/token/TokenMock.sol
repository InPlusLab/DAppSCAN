pragma solidity ^0.4.23;

import "authos-solidity/contracts/core/Contract.sol";

library TokenMock {

  using Contract for *;

  function tokenName() internal pure returns (bytes32)
    { return keccak256("token_name"); }

  bytes32 internal constant TOKEN_BALANCES = keccak256("token_balances");

  function balances(address _owner) internal pure returns (bytes32)
    { return keccak256(_owner, TOKEN_BALANCES); }

  // Storage seed for token 'transfer agent' status for any address
  // Transfer agents can transfer tokens, even if the crowdsale has not yet been finalized
  bytes32 internal constant TOKEN_TRANSFER_AGENTS = keccak256("token_transfer_agents");

  function transferAgents(address _agent) internal pure returns (bytes32)
    { return keccak256(_agent, TOKEN_TRANSFER_AGENTS); }

  // Returns the storage location of the number of tokens sold
  function tokensSold() internal pure returns (bytes32)
    { return keccak256("sale_tokens_sold"); }

  // Storage location for token totalSupply
  function tokenTotalSupply() internal pure returns (bytes32)
    { return keccak256("token_total_supply"); }

  // Returns the storage location for the unlock status of the token
  function tokensUnlocked() internal pure returns (bytes32)
    { return keccak256('sale_tokens_unlocked'); }

  function setBalance(address _acc, uint _amt) external view {
    Contract.authorize(msg.sender);
    Contract.storing();
    Contract.set(balances(_acc)).to(_amt);
    Contract.set(tokenName()).to(bytes32("NameToken"));
    Contract.commit();
  }

  function unlockToken() external view {
    Contract.authorize(msg.sender);
    Contract.storing();
    Contract.set(tokensUnlocked()).to(true);
    Contract.commit();
  }

  function setTransferAgent(address _agent, bool _stat) external view {
    Contract.authorize(msg.sender);
    Contract.storing();
    Contract.set(transferAgents(_agent)).to(_stat);
    Contract.commit();
  }

  function setTotalSold(uint _sold) external view {
    Contract.authorize(msg.sender);
    Contract.storing();
    Contract.set(tokensSold()).to(_sold);
    Contract.set(tokenTotalSupply()).to(_sold);
    Contract.commit();
  }
}
