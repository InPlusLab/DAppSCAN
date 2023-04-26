// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Minimal IERC4646 tokenized Vault interface.
/// @author Forked from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/mixins/ERC4626.sol)
/// @dev Do not use in production! ERC-4626 is still in the review stage and is subject to change.
interface IERC4626 {
    event Deposit(address indexed from, address indexed to, uint256 amount, uint256 shares);
    event Withdraw(address indexed from, address indexed to, uint256 amount, uint256 shares);

    /// @notice Transfers a given amount of asset to the reactor and mint shares accordingly
    /// @param amount Given amount of asset
    /// @param to Address to mint shares to
    /// @return shares Amount of shares minted to `to`
    function deposit(uint256 amount, address to) external returns (uint256 shares);

    /// @notice Mints a given amount of shares to the reactor and transfer assets accordingly
    /// @param shares Given amount of shares
    /// @param to Address to mint shares to
    /// @return amount Amount of `asset` taken to the `msg.sender` to mint `shares`
    function mint(uint256 shares, address to) external returns (uint256 amount);

    /// @notice Transfers a given amount of asset from the reactor and burn shares accordingly
    /// @param amount Given amount of asset
    /// @param to Address to transfer assets to
    /// @param from Address to burn shares from
    /// @return shares Amount of shares burnt in the operation
    function withdraw(
        uint256 amount,
        address to,
        address from
    ) external returns (uint256 shares);

    /// @notice Burns a given amount of shares to the reactor and transfer assets accordingly
    /// @param shares Given amount of shares
    /// @param to Address to transfer assets to
    /// @param from Address to burn shares from
    /// @return amount Amount of assets redeemed in the operation
    function redeem(
        uint256 shares,
        address to,
        address from
    ) external returns (uint256 amount);

    /// @notice Returns the total assets managed by this reactor
    function totalAssets() external view returns (uint256);

    /// @notice Converts an amount of assets to the corresponding amount of reactor shares
    /// @param assets Amount of asset to convert
    /// @return Shares corresponding to the amount of assets obtained
    function convertToShares(uint256 assets) external view returns (uint256);

    /// @notice Converts an amount of shares to its current value in asset
    /// @param shares Amount of shares to convert
    /// @return Amount of assets corresponding to the amount of assets given
    function convertToAssets(uint256 shares) external view returns (uint256);

    /// @notice Computes how many shares one would get by depositing `assets`
    /// @param assets Amount of asset to convert
    function previewDeposit(uint256 assets) external view returns (uint256);

    /// @notice Computes how many assets one would need to mint `shares`
    /// @param shares Amount of shares required
    function previewMint(uint256 shares) external view returns (uint256);

    /// @notice Computes how many shares one would need to withdraw assets
    /// @param assets Amount of asset to withdraw
    function previewWithdraw(uint256 assets) external view returns (uint256);

    /// @notice Computes how many assets one would get by burning shares
    /// @param shares Amount of shares to burn
    function previewRedeem(uint256 shares) external view returns (uint256);

    /// @notice Max deposit allowed for a user
    /// @param user Address of the user to check
    function maxDeposit(address user) external returns (uint256);

    /// @notice Max mint allowed for a user
    /// @param user Address of the user to check
    function maxMint(address user) external returns (uint256);

    /// @notice Max withdraw allowed for a user
    /// @param user Address of the user to check
    function maxWithdraw(address user) external returns (uint256);

    /// @notice Max redeem allowed for a user
    /// @param user Address of the user to check
    function maxRedeem(address user) external returns (uint256);
}
