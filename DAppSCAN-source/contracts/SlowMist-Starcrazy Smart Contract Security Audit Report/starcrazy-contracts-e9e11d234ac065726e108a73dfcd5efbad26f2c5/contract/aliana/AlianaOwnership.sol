pragma solidity ^0.5.0;

import "./AlianaBase.sol";
import "../token/IApproveAndCallFallBack.sol";

/// @title The facet of the GameAlianas core contract that manages ownership, ERC-721 (draft) compliant.
/// @dev Ref: https://github.com/ethereum/EIPs/issues/721
///  See the AlianaCore contract documentation to understand how the various contract facets are arranged.
contract AlianaOwnership is AlianaBase {
    /// @notice Returns the total number of Kitties currently in existence.
    function totalAlianaSupply() public view returns (uint256) {
        return alianas.length;
    }

    /// @notice Returns a list of all Aliana IDs assigned to an address.
    /// @param _owner The owner whose Kitties we are interested in.
    /// @dev This method MUST NEVER be called by smart contract code. First, it's fairly
    ///  expensive (it walks the entire Aliana array looking for cats belonging to owner),
    ///  but it also returns a dynamic array, which is only supported for web3 calls, and
    ///  not contract-to-contract calls.
    function tokensOfOwner(address _owner)
        external
        view
        returns (uint256[] memory ownerTokens)
    {
        return super._tokensOfOwner(_owner);
    }

    /// @notice `msg.sender` approves `spender_` to send `tokenId_` tokens on
    ///  its behalf, and then a function is triggered in the contract that is
    ///  being approved, `spender_`. This allows users to use their tokens to
    ///  interact with contracts in one function call instead of two
    /// @param spender_ The address of the contract able to transfer the tokens
    /// @param tokenId_ The id of tokens to be approved for transfer
    /// @return True if the function call was successful
    function approveAndCall(
        address spender_,
        uint256 tokenId_,
        bytes memory extraData_
    ) public returns (bool success) {
        approve(spender_, tokenId_);
        IApproveAndCallFallBack(spender_).receiveApproval(
            msg.sender,
            tokenId_,
            address(this),
            extraData_
        );
        return true;
    }

    function setApprovalForAllAndCall(
        address spender_,
        bool approved_,
        bytes memory extraData_
    ) public returns (bool success) {
        setApprovalForAll(spender_, approved_);
        IApproveAndCallFallBack(spender_).receiveApproval(
            msg.sender,
            uint256(-1),
            address(this),
            extraData_
        );
        return true;
    }
}
