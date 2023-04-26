// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "../interfaces/IAgToken.sol";
import "../interfaces/ITreasury.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";

/// @title BaseAgTokenSideChain
/// @author Angle Core Team
/// @notice Base Contract for Angle agTokens to be deployed on any other chain than Ethereum mainnet
/// @dev This type of contract can be used to create and handle the stablecoins of Angle protocol in different chains than Ethereum
contract BaseAgTokenSideChain is IAgToken, ERC20PermitUpgradeable {
    // ======================= Parameters and Variables ============================

    /// @inheritdoc IAgToken
    mapping(address => bool) public isMinter;
    /// @notice Reference to the treasury contract which can grant minting rights
    address public treasury;

    // ================================== Events ===================================

    event TreasuryUpdated(address indexed _treasury);
    event MinterToggled(address indexed minter);

    // =============================== Errors ================================

    error BurnAmountExceedsAllowance();
    error InvalidSender();
    error InvalidTreasury();
    error NotMinter();
    error NotTreasury();

    // ============================= Constructor ===================================

    /// @notice Initializes the contract
    /// @param name_ Name of the token
    /// @param symbol_ Symbol of the token
    /// @param _treasury Reference to the `Treasury` contract associated to this agToken implementation
    /// @dev By default, agTokens are ERC-20 tokens with 18 decimals
    function _initialize(
        string memory name_,
        string memory symbol_,
        address _treasury
    ) internal initializer {
        __ERC20Permit_init(name_);
        __ERC20_init(name_, symbol_);
        if (address(ITreasury(_treasury).stablecoin()) != address(this)) revert InvalidTreasury();
        treasury = _treasury;
        emit TreasuryUpdated(address(_treasury));
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    // =============================== Modifiers ===================================

    /// @notice Checks to see if it is the `Treasury` calling this contract
    /// @dev There is no Access Control here, because it can be handled cheaply through this modifier
    modifier onlyTreasury() {
        if (msg.sender != address(treasury)) revert NotTreasury();
        _;
    }

    /// @notice Checks whether the sender has the minting right
    modifier onlyMinter() {
        if (!isMinter[msg.sender]) revert NotMinter();
        _;
    }

    // =========================== External Function ===============================

    /// @notice Allows anyone to burn agToken without redeeming collateral back
    /// @param amount Amount of stablecoins to burn
    /// @dev This function can typically be called if there is a settlement mechanism to burn stablecoins
    function burnStablecoin(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // ======================= Minter Role Only Functions ==========================

    /// @inheritdoc IAgToken
    function burnSelf(uint256 amount, address burner) external onlyMinter {
        _burn(burner, amount);
    }

    /// @inheritdoc IAgToken
    function burnFrom(
        uint256 amount,
        address burner,
        address sender
    ) external onlyMinter {
        _burnFromNoRedeem(amount, burner, sender);
    }

    /// @inheritdoc IAgToken
    function mint(address account, uint256 amount) external onlyMinter {
        _mint(account, amount);
    }

    // ======================= Treasury Only Functions =============================

    /// @inheritdoc IAgToken
    function addMinter(address minter) external onlyTreasury {
        isMinter[minter] = true;
        emit MinterToggled(minter);
    }

    /// @inheritdoc IAgToken
    function removeMinter(address minter) external {
        if (msg.sender != address(treasury) && msg.sender != minter) revert InvalidSender();
        isMinter[minter] = false;
        emit MinterToggled(minter);
    }

    /// @inheritdoc IAgToken
    function setTreasury(address _treasury) external onlyTreasury {
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    // ============================ Internal Function ==============================

    /// @notice Internal version of the function `burnFromNoRedeem`
    /// @param amount Amount to burn
    /// @dev It is at the level of this function that allowance checks are performed
    function _burnFromNoRedeem(
        uint256 amount,
        address burner,
        address sender
    ) internal {
        if (burner != sender) {
            uint256 currentAllowance = allowance(burner, sender);
            if (currentAllowance < amount) revert BurnAmountExceedsAllowance();
            _approve(burner, sender, currentAllowance - amount);
        }
        _burn(burner, amount);
    }
}
