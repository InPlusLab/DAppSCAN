// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.6.11;

// ============ External Imports ============
import { TypedMemView } from "@summa-tx/memview-sol/contracts/TypedMemView.sol";
// ============ Internal Imports ============
import { CounterMessage } from "./CounterMessage.sol";
import { Router } from "./Router.sol";
import { XAppConnectionClient } from "./XAppConnectionClient.sol";

/*
============ Overview: Building a xApp ============
To implement a xApp, define the actions you would like to execute across chains.
For each type of action,
- in the Message library,
    - implement functions to *format* the message to send to the other chain 
    (encodes all necessary information for the action)
    - implement functions to *parse* the message once it is received on the 
    other chain (decode all necessary information for the action)
- in the xApp Router
    - implement a corresponding _handle function to receive, parse, and execute 
    the specific type of message from the remote domain
    - add logic to the global `handle` function to route incoming messages to 
    the appropriate _handle function

In this example, imagine you have two Counter apps on two different chains, 
chain A and chain B. The apps are simple. You can either increment or decrement 
the counter on that chain's app by a certain amount. To increment the counter 
on chain A, you must send an Increment message from the counter app on chain B 
to the counter app on chain A. If you would like to increment the counter on 
chain B, you must send an Increment message from the counter app on chain A to 
the counter app on chain B. Below, we define how to receive and act on the 
messages defined in CounterMessage.sol for this cross-chain Counter app.
*/
contract CounterRouter is Router {
  // ============ Libraries ============

  using TypedMemView for bytes;
  using TypedMemView for bytes29;
  using CounterMessage for bytes29;

  // ============ Public Storage ============

  int256 public count = 0;

  // ============ Events ============

  event Incremented(int256 indexed newValue);
  event Decremented(int256 indexed newValue);

  // ============ Constructor ============

  constructor(address _xAppConnectionManager) {
    __XAppConnectionClient_initialize(_xAppConnectionManager);
  }

  // ============ Handle message functions ============

  /**
   * @notice Receive messages sent via Nomad from other remote xApp Routers;
   * parse the contents of the message and enact the message's effects on the local chain
   * @dev Called by an Nomad Replica contract while processing a message sent via Nomad
   * @param _origin The domain the message is coming from
   * @param _nonce The unique identifier for the message from origin to destination
   * @param _sender The address the message is coming from
   * @param _message The message in the form of raw bytes
   */
  function handle(
    uint32 _origin,
    uint32 _nonce,
    bytes32 _sender,
    bytes memory _message
  ) external override onlyReplica onlyRemoteRouter(_origin, _sender) {
    bytes29 _msg = _message.ref(0);
    // route message to appropriate _handle function
    // based on what type of message is encoded
    if (_msg.isIncrement()) {
      _handleIncrement(_msg);
    } else if (_msg.isDecrement()) {
      _handleDecrement(_msg);
    } else {
      // if _message doesn't match any valid actions, revert
      require(false, "!valid action");
    }
  }

  /**
   * @notice Once the Router has parsed a message in the handle function and
   * determined it is type Increment, call this internal function to parse
   * the `amount` from the message and increment count.
   * @param _message The message in the form of raw bytes
   */
  function _handleIncrement(bytes29 _message) internal {
    uint256 _amount = _message.getAmount();
    count += int256(_amount);
    emit Incremented(count);
  }

  /**
   * @notice Once the Router has parsed a message in the handle function and
   * determined it is type Decrement, call this internal function to parse
   * the `amount` from the message and decrement count.
   * @param _message The message in the form of raw bytes
   */
  function _handleDecrement(bytes29 _message) internal {
    uint256 _amount = _message.getAmount();
    count -= int256(_amount);
    emit Decremented(count);
  }

  // ============ Dispatch message functions ============

  /**
   * @notice Send a message of type Increment to a remote xApp Router via Nomad;
   * processing this message on the destination chain will cause the remote
   * router on the destination chain to increment its count by `amount`.
   * @param _destinationDomain The domain to send the message to
   * @param _amount Amount to increment the remote router's count
   */
  function dispatchIncrement(uint32 _destinationDomain, uint256 _amount)
    external
  {
    // get the xApp Router address at the destinationDomain
    bytes32 _remoteRouterAddress = _mustHaveRemote(_destinationDomain);
    // encode a message to send to Increment to remote xApp Router
    bytes memory _incrementMessage = CounterMessage.formatIncrement(_amount);
    // send the message to the xApp Router
    _home().dispatch(
      _destinationDomain,
      _remoteRouterAddress,
      _incrementMessage
    );
  }

  /**
   * @notice Send a message of type Decrement to a remote xApp Router via Nomad;
   * processing this message on the destination chain will cause the remote
   * router on the destination chain to decrement its count by `amount`.
   * @param _destinationDomain The domain to send the message to
   * @param _amount Amount to increment the remote router's count
   */
  function dispatchDecrement(uint32 _destinationDomain, uint256 _amount)
    external
  {
    // get the xApp Router address at the destinationDomain
    bytes32 _remoteRouterAddress = _mustHaveRemote(_destinationDomain);
    // encode a message to send to Decrement to remote xApp Router
    bytes memory _decrementMessage = CounterMessage.formatDecrement(_amount);
    // send the message to the xApp Router
    _home().dispatch(
      _destinationDomain,
      _remoteRouterAddress,
      _decrementMessage
    );
  }
}
