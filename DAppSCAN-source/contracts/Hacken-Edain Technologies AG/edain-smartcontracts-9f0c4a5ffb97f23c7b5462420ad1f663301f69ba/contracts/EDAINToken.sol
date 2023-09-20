// SPDX-License-Identifier: MIT
// SWC-103-Floating Pragma: L3
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20SnapshotUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";

import "./EDAINStaking.sol";

contract EDAINToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20SnapshotUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ERC20CappedUpgradeable,
    EDAINStaking
{
    using SafeMathUpgradeable for uint256;

    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @notice Init function for the EDAIN token
     * @notice ERC20 token _name: EDAIN, _symbol: EAI, _decimals: 18
     * @notice Is burnable, allows token holders to destroy both their own tokens and those that they have an allowance for
     * @notice When a snapshot is created, the balances and total supply at the time are recorded for later access.
     * @notice Has a fixed total supply capped at 470.000.000 EAI
     * @notice ERC20 token with pausable function token transfers/minting/burning.
     */
    function initialize(uint256 initialMint) public initializer {
        __ERC20_init("EDAIN", "EAI");
        __ERC20Burnable_init();
        __ERC20Snapshot_init();
        __AccessControl_init();
        __Pausable_init();
        __EDAINStaking_init();
        __ERC20Capped_init(47e7 * 10**decimals());

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(SNAPSHOT_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);

        _mint(msg.sender, initialMint * 10**decimals());
    }

    /**
     * @notice Method to create a snapshop of the balances and supply
     */
    function snapshot() external onlyRole(SNAPSHOT_ROLE) {
        _snapshot();
    }

    /**
     * @notice Method to pause the transfer of token, minting and burning in case of emergency
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Method to unpause the transfer of token, minting and burning in case of emergency
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Public Method to mint new tokens
     * @param to The address of the recipient
     * @param amount The amount to be minted
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Internal Method to mint new tokens
     * @param account The address of the recipient
     * @param amount to be minted in uint256
     */
    function _mint(address account, uint256 amount)
        internal
        virtual
        override(ERC20Upgradeable, ERC20CappedUpgradeable)
        whenNotPaused
    {
        require(
            ERC20Upgradeable.totalSupply() + amount <= cap(),
            "ERC20Capped: cap exceeded"
        );
        super._mint(account, amount);
    }

    /**
     * @notice Hook method before any token transfer
     * @param from The address of the sender
     * @param to The address of the recipient
     * @param amount The amount to send
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    )
        internal
        override(ERC20Upgradeable, ERC20SnapshotUpgradeable)
        whenNotPaused
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @notice Public method to create stake by any token holders
     * @param amount The amount to create from stakes
     */
    function stake(uint256 amount) external {
        require(
            msg.sender != address(0x00),
            "ERC20: Add stake from zero address"
        );
        require(
            amount < balanceOf(msg.sender),
            "ERC20: Balance of the sender is lower than the staked amount"
        );

        _burn(msg.sender, amount);
        _stake(amount);
    }

    /**
     * @notice Public method to withdraw stake and rewards
     * @param amount The amount to withdraw from stakes
     * @param stake_index the index of the stake
     */
    function withdrawStake(uint256 amount, uint256 stake_index) external {
        uint256 amount_to_mint = _withdrawStake(amount, stake_index);
        // Return staked tokens to user
        _mint(msg.sender, amount_to_mint);
    }
}
