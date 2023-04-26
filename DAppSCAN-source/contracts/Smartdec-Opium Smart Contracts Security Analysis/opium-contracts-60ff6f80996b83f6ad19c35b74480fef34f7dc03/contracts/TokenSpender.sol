pragma solidity ^0.5.4;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";

import "erc721o/contracts/Interfaces/IERC721O.sol";

import "./Lib/WhitelistedWithGovernanceAndChangableTimelock.sol";

/// @title Opium.TokenSpender contract holds users ERC20 approvals and allows whitelisted contracts to use tokens
contract TokenSpender is WhitelistedWithGovernanceAndChangableTimelock {
    using SafeERC20 for IERC20;

    // Initial timelock period
    uint256 public constant WHITELIST_TIMELOCK = 1 hours;

    /// @notice Calls constructors of super-contracts
    /// @param _governor address Address of governor, who is allowed to adjust whitelist
    constructor(address _governor) public WhitelistedWithGovernance(WHITELIST_TIMELOCK, _governor) {}

    /// @notice Using this function whitelisted contracts could call ERC20 transfers
    /// @param token IERC20 Instance of token
    /// @param from address Address from which tokens are transferred
    /// @param to address Address of tokens receiver
    /// @param amount uint256 Amount of tokens to be transferred
    function claimTokens(IERC20 token, address from, address to, uint256 amount) external onlyWhitelisted {
        token.safeTransferFrom(from, to, amount);
    }

    /// @notice Using this function whitelisted contracts could call ERC721O transfers
    /// @param token IERC721O Instance of token
    /// @param from address Address from which tokens are transferred
    /// @param to address Address of tokens receiver
    /// @param tokenId uint256 Token ID to be transferred
    /// @param amount uint256 Amount of tokens to be transferred
    function claimPositions(IERC721O token, address from, address to, uint256 tokenId, uint256 amount) external onlyWhitelisted {
        token.safeTransferFrom(from, to, tokenId, amount);
    }
}
