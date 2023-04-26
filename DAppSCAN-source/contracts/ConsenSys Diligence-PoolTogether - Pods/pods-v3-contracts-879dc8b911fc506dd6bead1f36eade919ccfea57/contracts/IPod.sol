// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0 <0.8.0;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// @title The PoolTogether Pod specification
interface IPod is IERC20Upgradeable {
    /// @notice Returns the address of the prize pool that the pod is bound to
    /// @return The address of the prize pool
    function prizePool() external view returns (address);

    /// @notice Allows a user to deposit into the Pod
    /// @param to The address that shall receive the Pod shares
    /// @param tokenAmount The amount of tokens to deposit.  These are the same tokens used to deposit into the underlying prize pool.
    /// @return The number of Pod shares minted.
    function depositTo(address to, uint256 tokenAmount)
        external
        returns (uint256);

    /// @notice Withdraws a users share of the prize pool.
    /// @dev The function should first withdraw from the 'float'; i.e. the funds that have not yet been deposited.
    /// if the withdraw is for more funds that can be covered by the float, then a withdrawal is made against the underlying
    /// prize pool.  The user will be charged the prize pool's exit fee on the underlying funds.  The fee can be calculated using PrizePool#calculateEarlyExitFee()
    /// @param shareAmount The number of Pod shares to redeem
    /// @return The actual amount of tokens that were transferred to the user.  This is the same as the deposit token.
    function withdraw(uint256 shareAmount) external returns (uint256);

    /// @notice Calculates the token value per Pod share.
    /// @dev This is useful for those who wish to calculate their balance.
    /// @return The token value per Pod share.
    function getPricePerShare() external view returns (uint256);

    /// @notice Allows someone to batch deposit funds into the underlying prize pool.  This should be called periodically.
    /// @dev This function should deposit the float into the prize pool, and claim any POOL tokens and distribute to users (possibly via adaptation of Token Faucet)
    function batch(uint256 batchAmount) external returns (bool);

    /// @notice Allows the owner of the Pod or the asset manager to withdraw tokens from the Pod.
    /// @dev This function should disallow the withdrawal of tickets or POOL to prevent users from being rugged.
    /// @param token The ERC20 token to withdraw.  Must not be prize pool tickets or POOL tokens.
    function withdrawERC20(IERC20Upgradeable token, uint256 amount)
        external
        returns (bool);

    /// @notice Allows the owner of the Pod or the asset manager to withdraw tokens from the Pod.
    /// @dev This is mainly for Loot Boxes; so Loot Boxes that are won can be transferred out.
    /// @param token The address of the ERC721 to withdraw
    /// @param tokenId The token id to withdraw
    function withdrawERC721(IERC721 token, uint256 tokenId)
        external
        returns (bool);

    /// @notice Allows a user to claim POOL tokens for an address.  The user will be transferred their share of POOL tokens.
    function claim(address user, address token) external returns (uint256);
}
