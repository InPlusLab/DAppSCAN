// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.6.11;

import "@summa-tx/memview-sol/contracts/TypedMemView.sol";

/*
============ Overview: xApp Message Library ============
Messages are the actual data passed between chains.
We define messages as a byte vector in memory.

To make sure that messages are compact and chain agnostic,
we recommend a simple, custom serialization format (rather than ABI encoding).

Message Flow Between xApps:
1. xApp Router A receives a command on chain A
2. xApp Router A encodes (formats) the information into a message
2. xApp Router A sends the message to xApp Router B on chain B via Nomad
3. xApp Router B receives the message via Nomad
4. xApp Router B decodes (gets) the information from the message and acts on it

The Message Library should contain the following for each type of message:
1. Formatter: a function which takes information as Solidity arguments and
   encodes it as a byte vector in a defined format, producing the message

2. Identifier: a function which takes a byte vector and returns TRUE
   if the vector is matches the expected format of this message type

3. Getter(s): function(s) which parse the information stored in the message
   and return them in the form of Solidity arguments

TypedMemView is a library for working with memory in Solidity.
We use TypedMemView (bytes29 view) to create a custom serialization format for xApp messages. A bytes29 view uses a 1-byte type tag on the front of the array to denote the message type. When getting a reference to a bytes29 view using `view.ref(0)`, it gives you a reference to the array 1-byte beyond the start, thus skipping over the type tag and starting at the data. Thus, indexing functions for bytes29 start at the actual data. To access the bytes29 message type (encoded in the tag), we can call `view.typeOf()`. There are more details below.

Example using TypedMemView:
- lets say we want to send a message that specifies that we want to send some 
  amount of tokens of a given token id to a recipient address
- lets say the message enum Type is of Type.Send = 1 (this is the internal 
  1-byte tag used to denote the message type)
- lets say tokenId is a 4 byte uint, amount is a 32 byte uint, and recipient is 
  a 32 byte address

Data                   || Type.Send  ||  tokenId  |  amount  |  recipient  |
====================== || ==================================================
Index (using `ref(0)`) || -- ignore - 0 --------- 4 -------- 36 --------- 68
====================== || ==================================================
# of bytes             ||   1 byte   ||  4 bytes  | 32 bytes |   32 bytes  |

If we want to format a Send message, the formatter would look like:
function formatSend(uint32 tokenId, uint256 amount, bytes32 recipient) 
    internal 
    pure 
    returns (bytes memory)
{
    return abi.encodePacked(Types.Send, tokenId, amount, recipient);
}

If we have received a message as a byte array and want to check if its of type 
Send, we can do the following:
function isTypeSend(byte memory message) internal pure returns (bool) {
    bytes29 _view = message.ref(0); // create bytes29 view
    return uint8(_view.typeOf()) == Types.Send;
}

If we want to parse a Send message, our getters would look like:
function getTokenId(bytes memory message) 
    internal 
    pure 
    returns (uint32)
{
    // create bytes29 slice
    bytes29 _view = message.ref(0); 

    // return the first 4 bytes of data
    return _view.indexUint(0, 4); 
}

function getAmount(bytes memory message) 
    internal 
    pure 
    returns (uint256)
{
  // create bytes29 slice
    bytes29 _view = message.ref(0); 

    // return the next 32 bytes starting at byte 4
    return _view.indexUint(4, 32); 
}

function getRecipient(bytes memory message) 
    internal 
    pure 
    returns (uint32)
{
    // create bytes29 slice
    bytes29 _view = message.ref(0);

    // return the next 32 bytes starting at byte 36 
    return _view.indexUint(36, 32); 
}

In this example, imagine you have two Counter apps on two different chains, 
chain A and chain B. The apps are simple. You can either increment or decrement 
the counter on that chain's app by a certain amount. To increment the counter 
on chain A, you must send an Increment message from the counter app on chain B 
to the counter app on chain A. If you would like to increment the counter on 
chain B, you must send an Increment message from the counter app on chain A to 
the counter app on chain B. Below, we define how to define, format, and parse messages specific to this cross-chain Counter app.
*/
library CounterMessage {
  using TypedMemView for bytes;
  using TypedMemView for bytes29;

  enum Types {
    Invalid, // 0
    Inc, // 1 - increment count
    Dec // 2 - decrement count
  }

  // ============ Formatters ============

  /**
   * @notice Given the amount you want to increment count on the receiving
   * chain's contract, format a bytes message encoding the information
   * @param _amount The amount to increment the remote contract's count
   * @return The encoded bytes message
   */
  function formatIncrement(uint256 _amount)
    internal
    pure
    returns (bytes memory)
  {
    return abi.encodePacked(uint8(Types.Inc), _amount);
  }

  /**
   * @notice Given the amount you want to decrement count on the receiving
   * chain's contract, format a bytes message encoding the information
   * @param _amount The amount to decrement the remote contract's count
   * @return The encoded bytes message
   */
  function formatDecrement(uint256 _amount)
    internal
    pure
    returns (bytes memory)
  {
    return abi.encodePacked(uint8(Types.Dec), _amount);
  }

  // ============ Identifiers ============

  /**
   * @notice Get the type that the TypedMemView is cast to
   * @param _view The message
   * @return _type The type of the message (one of the enum Types)
   */
  function messageType(bytes29 _view) internal pure returns (Types _type) {
    _type = Types(uint8(_view.typeOf()));
  }

  /**
   * @notice Determine whether the message is an Increment message
   * @param _view The message
   * @return _isIncrement True if the message is of type Increment
   */
  function isIncrement(bytes29 _view)
    internal
    pure
    returns (bool _isIncrement)
  {
    _isIncrement = messageType(_view) == Types.Inc;
  }

  /**
   * @notice Determine whether the message is an Decrement message
   * @param _view The message
   * @return _isDecrement True if the message is of type Decrement
   */
  function isDecrement(bytes29 _view)
    internal
    pure
    returns (bool _isDecrement)
  {
    _isDecrement = messageType(_view) == Types.Dec;
  }

  // ============ Getters ============

  /**
   * @notice Parse the amount sent within an Increment or Decrement message
   * @param _view The message
   * @return _amount The amount encoded in the message
   */
  function getAmount(bytes29 _view) internal pure returns (uint256 _amount) {
    require(
      isIncrement(_view) || isDecrement(_view),
      "MessageTemplate/number: view must be of type increment or decrement"
    );

    // bytes 0 to 32 are the amount field for an Inc/Dec message
    _amount = uint256(_view.index(0, 32));
  }
}
