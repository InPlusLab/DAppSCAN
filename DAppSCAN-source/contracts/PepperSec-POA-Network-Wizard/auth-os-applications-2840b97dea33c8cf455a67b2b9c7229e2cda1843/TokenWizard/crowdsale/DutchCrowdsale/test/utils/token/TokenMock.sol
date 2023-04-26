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

  // Whether or not the crowdsale is post-purchase
  function isFinished() internal pure returns (bytes32)
    { return keccak256("sale_is_completed"); }

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
    Contract.set(isFinished()).to(true);
    Contract.commit();
  }

  function setTransferAgent(address _agent, bool _stat) external view {
    Contract.authorize(msg.sender);
    Contract.storing();
    Contract.set(transferAgents(_agent)).to(_stat);
    Contract.commit();
  }
}
