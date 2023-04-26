// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../interfaces/IERC721.sol";


// Contract to test safe transfer behavior.
contract ERC721ReceiverMock {

  bytes4 constant internal ERC721_RECEIVED_SIG = 0x150b7a02;
  bytes4 constant internal ERC721_RECEIVED_INVALID = 0xdeadbeef;
  bytes4 constant internal IS_ERC721_RECEIVER = 0x150b7a02;

  // Keep values from last received contract.
  bool public shouldReject;

  bytes public lastData;
  address public lastOperator;
  uint256 public lastId;
  uint256 public lastValue;

  //Debug event
  event TransferReceiver(address _from, address _to, uint256 _fromBalance, uint256 _toBalance, address _tokenOwner);

  /**
   * @notice Indicates whether a contract implements the `ERC721TokenReceiver` functions and so can accept ERC721 token types.
   * @param  interfaceID The ERC-165 interface ID that is queried for support.s
   * @dev This function MUST return true if it implements the ERC721TokenReceiver interface and ERC-165 interface.
   *      This function MUST NOT consume more than 5,000 gas.
   * @return Wheter ERC-165 or ERC721TokenReceiver interfaces are supported.
   */
  function supportsInterface(bytes4 interfaceID)
      external
      pure
      returns (bool)
  {
      return  interfaceID == 0x01ffc9a7 || // ERC-165 support (i.e. `bytes4(keccak256('supportsInterface(bytes4)'))`).
          interfaceID == IS_ERC721_RECEIVER;         // ERC-721 `ERC721TokenReceiver` support
  }

  /**
   * @notice Handle the receipt of a single ERC721 token type.
   * @dev An ERC721-compliant smart contract MUST call this function on the token recipient contract, at the end of a `safeTransferFrom` after the balance has been updated.
   * This function MAY throw to revert and reject the transfer.
   * Return of other than the magic value MUST result in the transaction being reverted.
   * Note: The contract address is always the message sender.
   * @param _from      The address which previously owned the token
   * @param _tokenId   The token id
   * @param _data      Additional data with no specified format
   * @return           `bytes4(keccak256("onERC721Received(address,address,uint256,uint256,bytes)"))`
   */
  function onERC721Received(
      address,
      address _from,
      uint256 _tokenId,
      bytes memory _data
  )
      public
      returns(bytes4)
  {
      // To check the following conditions;
      //   All the balances in the transfer MUST have been updated to match the senders intent before any hook is called on a recipient.
      //   All the transfer events for the transfer MUST have been emitted to reflect the balance changes before any hook is called on a recipient.
      //   If data is passed, must be specific
      uint256 fromBalance = IERC721(msg.sender).balanceOf(_from);
      uint256 toBalance = IERC721(msg.sender).balanceOf(address(this));
      address tokenOwner = IERC721(msg.sender).ownerOf(_tokenId);
      emit TransferReceiver(_from, address(this), fromBalance, toBalance, tokenOwner);

      if (_data.length != 0) {
          require(
              keccak256(_data) == keccak256(abi.encodePacked("Hello from the other side")),
              "ERC721ReceiverMock#onERC721Received: UNEXPECTED_DATA"
          );
      }

      if (shouldReject == true) {
          return ERC721_RECEIVED_INVALID; // Some random value
      } else {
          return ERC721_RECEIVED_SIG;
      }
  }

  function setShouldReject(bool _value)
      public
  {
      shouldReject = _value;
  }
}
