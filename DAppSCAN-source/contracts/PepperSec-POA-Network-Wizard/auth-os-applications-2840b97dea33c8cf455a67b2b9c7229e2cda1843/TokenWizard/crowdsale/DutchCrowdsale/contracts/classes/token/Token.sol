pragma solidity ^0.4.23;

import "authos-solidity/contracts/core/Contract.sol";

library Transfer {

  using Contract for *;

  // 'Transfer' event topic signature
  bytes32 private constant TRANSFER_SIG = keccak256('Transfer(address,address,uint256)');

  // Returns the topics for a Transfer event -
  function TRANSFER (address _owner, address _dest) private pure returns (bytes32[3] memory)
    { return [TRANSFER_SIG, bytes32(_owner), bytes32(_dest)]; }

  // Ensures the sender is a transfer agent, or that the tokens are unlocked
  function canTransfer() internal view {
    if (
      Contract.read(Token.transferAgents(Contract.sender())) == 0 &&
      Contract.read(Token.isFinished()) == 0
    ) revert('transfers are locked');
  }

  // Implements the logic for a token transfer -
  function transfer(address _dest, uint _amt) internal view {
    // Ensure valid input -
    if (_dest == 0)
      revert('invalid recipient');

    // Ensure the sender can currently transfer tokens
    Contract.checks(canTransfer);

    // Begin updating balances -
    Contract.storing();
    // Update sender token balance - reverts in case of underflow
    Contract.decrease(Token.balances(Contract.sender())).by(_amt);
    // Update recipient token balance - reverts in case of overflow
    Contract.increase(Token.balances(_dest)).by(_amt);

    // Finish updating balances: log event -
    Contract.emitting();
    // Log 'Transfer' event
    Contract.log(
      TRANSFER(Contract.sender(), _dest), bytes32(_amt)
    );
  }

  // Implements the logic for a token transferFrom -
  function transferFrom(address _owner, address _dest, uint _amt) internal view {
    // Ensure valid input -
    if (_dest == 0)
      revert('invalid recipient');
    if (_owner == 0)
      revert('invalid owner');

    // Owner must be able to transfer tokens -
    if (
      Contract.read(Token.transferAgents(_owner)) == 0 &&
      Contract.read(Token.isFinished()) == 0
    ) revert('transfers are locked');

    // Begin updating balances -
    Contract.storing();
    // Update spender token allowance - reverts in case of underflow
    Contract.decrease(Token.allowed(_owner, Contract.sender())).by(_amt);
    // Update owner token balance - reverts in case of underflow
    Contract.decrease(Token.balances(_owner)).by(_amt);
    // Update recipient token balance - reverts in case of overflow
    Contract.increase(Token.balances(_dest)).by(_amt);

    // Finish updating balances: log event -
    Contract.emitting();
    // Log 'Transfer' event
    Contract.log(
      TRANSFER(_owner, _dest), bytes32(_amt)
    );
  }
}

library Approve {

  using Contract for *;

  // event Approval(address indexed owner, address indexed spender, uint tokens)
  bytes32 internal constant APPROVAL_SIG = keccak256('Approval(address,address,uint256)');

  // Returns the events and data for an 'Approval' event -
  function APPROVAL (address _owner, address _spender) private pure returns (bytes32[3] memory)
    { return [APPROVAL_SIG, bytes32(_owner), bytes32(_spender)]; }

  // Implements the logic to create the storage buffer for a Token Approval
  function approve(address _spender, uint _amt) internal pure {
    // Begin storing values -
    Contract.storing();
    // Store the approved amount at the sender's allowance location for the _spender
    Contract.set(Token.allowed(Contract.sender(), _spender)).to(_amt);
    // Finish storing, and begin logging events -
    Contract.emitting();
    // Log 'Approval' event -
    Contract.log(
      APPROVAL(Contract.sender(), _spender), bytes32(_amt)
    );
  }

  // Implements the logic to create the storage buffer for a Token Approval
  function increaseApproval(address _spender, uint _amt) internal view {
    // Begin storing values -
    Contract.storing();
    // Store the approved amount at the sender's allowance location for the _spender
    Contract.increase(Token.allowed(Contract.sender(), _spender)).by(_amt);
    // Finish storing, and begin logging events -
    Contract.emitting();
    // Log 'Approval' event -
    Contract.log(
      APPROVAL(Contract.sender(), _spender), bytes32(_amt)
    );
  }

  // Implements the logic to create the storage buffer for a Token Approval
  function decreaseApproval(address _spender, uint _amt) internal view {
    // Begin storing values -
    Contract.storing();
    // Decrease the spender's approval by _amt to a minimum of 0 -
    Contract.decrease(Token.allowed(Contract.sender(), _spender)).byMaximum(_amt);
    // Finish storing, and begin logging events -
    Contract.emitting();
    // Log 'Approval' event -
    Contract.log(
      APPROVAL(Contract.sender(), _spender), bytes32(_amt)
    );
  }
}

library Token {

  using Contract for *;

  /// SALE ///

  // Whether or not the crowdsale is post-purchase
  function isFinished() internal pure returns (bytes32)
    { return keccak256("sale_is_completed"); }

  /// TOKEN ///

  // Storage location for token name
  function tokenName() internal pure returns (bytes32)
    { return keccak256("token_name"); }

  // Storage seed for user balances mapping
  bytes32 internal constant TOKEN_BALANCES = keccak256("token_balances");

  function balances(address _owner) internal pure returns (bytes32)
    { return keccak256(_owner, TOKEN_BALANCES); }

  // Storage seed for user allowances mapping
  bytes32 internal constant TOKEN_ALLOWANCES = keccak256("token_allowances");

  function allowed(address _owner, address _spender) internal pure returns (bytes32)
    { return keccak256(_spender, keccak256(_owner, TOKEN_ALLOWANCES)); }

  // Storage seed for token 'transfer agent' status for any address
  // Transfer agents can transfer tokens, even if the crowdsale has not yet been finalized
  bytes32 internal constant TOKEN_TRANSFER_AGENTS = keccak256("token_transfer_agents");

  function transferAgents(address _agent) internal pure returns (bytes32)
    { return keccak256(_agent, TOKEN_TRANSFER_AGENTS); }

  /// CHECKS ///

  // Ensures the sale's token has been initialized
  function tokenInit() internal view {
    if (Contract.read(tokenName()) == 0)
      revert('token not initialized');
  }

  // Ensures both storage and events have been pushed to the buffer
  function emitAndStore() internal pure {
    if (Contract.emitted() == 0 || Contract.stored() == 0)
      revert('invalid state change');
  }

  /// FUNCTIONS ///

  /*
  Allows a token holder to transfer tokens to another address

  @param _to: The destination that will recieve tokens
  @param _amount: The number of tokens to transfer
  */
  function transfer(address _to, uint _amount) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the token is initialized -
    Contract.checks(tokenInit);
    // Execute transfer function -
    Transfer.transfer(_to, _amount);
    // Ensures state change will only affect storage and events -
    Contract.checks(emitAndStore);
    // Commit state changes to storage -
    Contract.commit();
  }

  /*
  Allows an approved spender to transfer tokens to another address on an owner's behalf

  @param _owner: The address from which tokens will be sent
  @param _recipient: The destination to which tokens will be sent
  @param _amount: The number of tokens to transfer
  */
  function transferFrom(address _owner, address _recipient, uint _amount) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the token is initialized -
    Contract.checks(tokenInit);
    // Execute transfer function -
    Transfer.transferFrom(_owner, _recipient, _amount);
    // Ensures state change will only affect storage and events -
    Contract.checks(emitAndStore);
    // Commit state changes to storage -
    Contract.commit();
  }

  /*
  Approves a spender to spend an amount of your tokens on your behalf

  @param _spender: The address allowed to spend your tokens
  @param _amount: The number of tokens that will be approved
  */
  function approve(address _spender, uint _amount) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the token is initialized -
    Contract.checks(tokenInit);
    // Execute approval function -
    Approve.approve(_spender, _amount);
    // Ensures state change will only affect storage and events -
    Contract.checks(emitAndStore);
    // Commit state changes to storage -
    Contract.commit();
  }

  /*
  Increases a spender's approval amount

  @param _spender: The address allowed to spend your tokens
  @param _amount: The amount by which the spender's allowance will be increased
  */
  function increaseApproval(address _spender, uint _amount) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the token is initialized -
    Contract.checks(tokenInit);
    // Execute approval function -
    Approve.increaseApproval(_spender, _amount);
    // Ensures state change will only affect storage and events -
    Contract.checks(emitAndStore);
    // Commit state changes to storage -
    Contract.commit();
  }

  /*
  Decreases a spender's approval amount

  @param _spender: The address allowed to spend your tokens
  @param _amount: The amount by which the spender's allowance will be decreased
  */
  function decreaseApproval(address _spender, uint _amount) external view {
    // Begin execution - reads execution id and original sender address from storage
    Contract.authorize(msg.sender);
    // Check that the token is initialized -
    Contract.checks(tokenInit);
    // Execute approval function -
    Approve.decreaseApproval(_spender, _amount);
    // Ensures state change will only affect storage and events -
    Contract.checks(emitAndStore);
    // Commit state changes to storage -
    Contract.commit();
  }
}
