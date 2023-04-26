pragma solidity ^0.5.0;

/// @dev The token _controller contract must implement these functions
contract ITokenController {
    /// @notice Called when `owner_` sends ether to the MiniMe Token contract
    /// @param owner_ The address that sent the ether to create tokens
    /// @return True if the ether is accepted, false if it throws
    function proxyPayment(
        address owner_,
        bytes4 sig,
        bytes memory data
    ) public payable returns (bool);

    /// @notice Notifies the _controller about a token transfer allowing the
    ///  _controller to react if desired
    /// @param from_ The origin of the transfer
    /// @param to_ The destination of the transfer
    /// @param amount_ The amount of the transfer
    /// @return False if the _controller does not authorize the transfer
    function onTransfer(
        address from_,
        address to_,
        uint256 amount_
    ) public returns (bool);

    /// @notice Notifies the _controller about an approval allowing the
    ///  _controller to react if desired
    /// @param owner_ The address that calls `approve()`
    /// @param spender_ The spender in the `approve()` call
    /// @param amount_ The amount in the `approve()` call
    /// @return False if the _controller does not authorize the approval
    function onApprove(
        address owner_,
        address spender_,
        uint256 amount_
    ) public returns (bool);
}
