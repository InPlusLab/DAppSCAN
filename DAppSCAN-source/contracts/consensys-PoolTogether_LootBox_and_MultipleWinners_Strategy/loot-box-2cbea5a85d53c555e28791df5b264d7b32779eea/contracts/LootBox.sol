// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// @title Allows anyone to "loot" an address
/// @author Brendan Asselstine
/// @notice A LootBox allows anyone to withdraw all tokens or execute calls on behalf of the contract.
/// @dev This contract is intended to be counterfactually instantiated via CREATE2.
contract LootBox {

  /// @notice A structure to define arbitrary contract calls
  struct Call {
    address to;
    uint256 value;
    bytes data;
  }

  /// @notice A structure to define ERC721 transfer contents
  struct WithdrawERC721 {
    IERC721 token;
    uint256[] tokenIds;
  }

  /// @notice A structure to define ERC1155 transfer contents
  struct WithdrawERC1155 {
    IERC1155 token;
    uint256[] ids;
    uint256[] amounts;
    bytes data;
  }

  /// @notice Emitted when an ERC20 token is withdrawn
  event WithdrewERC20(address indexed token, uint256 amount);

  /// @notice Emitted when an ERC721 token is withdrawn
  event WithdrewERC721(address indexed token, uint256[] tokenIds);

  /// @notice Emitted when an ERC1155 token is withdrawn
  event WithdrewERC1155(address indexed token, uint256[] ids, uint256[] amounts, bytes data);

  /// @notice Emitted when the contract transfer ether
  event TransferredEther(address indexed to, uint256 amount);

  /// @notice Executes calls on behalf of this contract.
  /// @param calls The array of calls to be executed.
  /// @return An array of the return values for each of the calls
  function executeCalls(Call[] calldata calls) external returns (bytes[] memory) {
    bytes[] memory response = new bytes[](calls.length);
    for (uint256 i = 0; i < calls.length; i++) {
      response[i] = _executeCall(calls[i].to, calls[i].value, calls[i].data);
    }
    return response;
  }

  /// @notice Transfers ether held by the contract to another account
  /// @param to The account to transfer Ether to
  /// @param amount The amount of Ether to transfer
  // SWC-100-Function Default Visibility: L64-L68
  function transferEther(address payable to, uint256 amount) public {
    to.transfer(amount);

    emit TransferredEther(to, amount);
  }

  /// @notice Transfers tokens to another account
  /// @param erc20 Array of ERC20 token addresses whose entire balance should be transferred
  /// @param erc721 Array of WithdrawERC721 structs whose tokens should be transferred
  /// @param erc1155 Array of WithdrawERC1155 structs whose tokens should be transferred
  /// @param to The address receiving all tokens
  function plunder(
    IERC20[] memory erc20,
    WithdrawERC721[] memory erc721,
    WithdrawERC1155[] memory erc1155,
    address payable to
  ) external {
    _withdrawERC20(erc20, to);
    _withdrawERC721(erc721, to);
    _withdrawERC1155(erc1155, to);
    transferEther(to, address(this).balance);
  }

  /// @notice Destroys this contract using `selfdestruct`
  /// @param to The address to send remaining Ether to
  function destroy(address payable to) external {
    selfdestruct(to);
  }

  /// @notice Executes a call to another contract
  /// @param to The address to call
  /// @param value The Ether to pass along with the call
  /// @param data The call data
  /// @return The return data from the call
  function _executeCall(address to, uint256 value, bytes memory data) internal returns (bytes memory) {
    (bool succeeded, bytes memory returnValue) = to.call{value: value}(data);
    require(succeeded, string(returnValue));
    return returnValue;
  }

  /// @notice Transfers the entire balance of ERC20s to an account
  /// @param tokens An array of ERC20 tokens to transfer out.  The balance of each will be transferred.
  /// @param to The recipient of the transfers
  function _withdrawERC20(IERC20[] memory tokens, address to) internal {
    for (uint256 i = 0; i < tokens.length; i++) {
      uint256 balance = tokens[i].balanceOf(address(this));
      tokens[i].transfer(to, balance);

      emit WithdrewERC20(address(tokens[i]), balance);
    }
  }

  /// @notice Transfers ERC721 tokens to an account
  /// @param withdrawals An array of WithdrawERC721 structs that each include the ERC721 token to transfer and the corresponding token ids.
  /// @param to The recipient of the transfers
  function _withdrawERC721(WithdrawERC721[] memory withdrawals, address to) internal {
    for (uint256 i = 0; i < withdrawals.length; i++) {
      for (uint256 tokenIndex = 0; tokenIndex < withdrawals[i].tokenIds.length; tokenIndex++) {
        withdrawals[i].token.transferFrom(address(this), to, withdrawals[i].tokenIds[tokenIndex]);
      }

      emit WithdrewERC721(address(withdrawals[i].token), withdrawals[i].tokenIds);
    }
  }

  /// @notice Transfers ERC1155 tokens to an account
  /// @param withdrawals An array of WithdrawERC1155 structs that each include the ERC1155 to transfer and it's corresponding token ids and amounts.
  /// @param to The recipient of the transfers
  function _withdrawERC1155(WithdrawERC1155[] memory withdrawals, address to) internal {
    for (uint256 i = 0; i < withdrawals.length; i++) {
      withdrawals[i].token.safeBatchTransferFrom(address(this), to, withdrawals[i].ids, withdrawals[i].amounts, withdrawals[i].data);

      emit WithdrewERC1155(address(withdrawals[i].token), withdrawals[i].ids, withdrawals[i].amounts, withdrawals[i].data);
    }
  }

}
