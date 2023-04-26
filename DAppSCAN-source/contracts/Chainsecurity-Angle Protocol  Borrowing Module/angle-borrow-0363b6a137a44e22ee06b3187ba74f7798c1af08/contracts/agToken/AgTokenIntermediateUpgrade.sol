// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "../interfaces/IAgToken.sol";
import "../interfaces/coreModule/IStableMaster.sol";
// OpenZeppelin may update its version of the ERC20PermitUpgradeable token
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";

/// @title AgTokenIntermediateUpgrade
/// @author Angle Core Team
/// @notice Base contract for agToken, that is to say Angle's stablecoins
/// @dev This contract is used to create and handle the stablecoins of Angle protocol
/// @dev It is still possible for any address to burn its agTokens without redeeming collateral in exchange
/// @dev This contract is the upgraded version of the AgToken that was first deployed on Ethereum mainnet and is used to
/// add other minters as needed by AMOs
contract AgTokenIntermediateUpgrade is ERC20PermitUpgradeable {
    // ========================= References to other contracts =====================

    /// @notice Reference to the `StableMaster` contract associated to this `AgToken`
    address public stableMaster;

    // ============================= Constructor ===================================

    /// @notice Initializes the `AgToken` contract
    /// @param name_ Name of the token
    /// @param symbol_ Symbol of the token
    /// @param stableMaster_ Reference to the `StableMaster` contract associated to this agToken
    /// @dev By default, agTokens are ERC-20 tokens with 18 decimals
    function initialize(
        string memory name_,
        string memory symbol_,
        address stableMaster_
    ) external initializer {
        __ERC20Permit_init(name_);
        __ERC20_init(name_, symbol_);
        require(stableMaster_ != address(0), "0");
        stableMaster = stableMaster_;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    // ======= Added Parameters and Variables from the first implementation ========

    /// @notice Checks whether an address has the right to mint agTokens
    mapping(address => bool) public isMinter;

    // =============================== Added Events ================================

    event MinterToggled(address indexed minter);

    // =============================== Setup Function ==============================

    /// @notice Sets up the minter role and gives it to the governor
    /// @dev This function just has to be called once
    function setUpMinter() external {
        address governor = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;
        require(msg.sender == governor);
        isMinter[governor] = true;
        emit MinterToggled(governor);
    }

    // =============================== Modifiers ===================================

    /// @notice Checks whether the sender has the minting right
    modifier onlyMinter() {
        require(isMinter[msg.sender] || msg.sender == stableMaster, "35");
        _;
    }

    // ========================= External Functions ================================
    // The following functions allow anyone to burn stablecoins without redeeming collateral
    // in exchange for that

    /// @notice Destroys `amount` token from the caller without giving collateral back
    /// @param amount Amount to burn
    /// @param poolManager Reference to the `PoolManager` contract for which the `stocksUsers` will
    /// need to be updated
    /// @dev When calling this function, people should specify the `poolManager` for which they want to decrease
    /// the `stocksUsers`: this is a way for the protocol to maintain healthy accounting variables
    function burnNoRedeem(uint256 amount, address poolManager) external {
        _burn(msg.sender, amount);
        IStableMaster(stableMaster).updateStocksUsers(amount, poolManager);
    }

    /// @notice Burns `amount` of agToken on behalf of another account without redeeming collateral back
    /// @param account Account to burn on behalf of
    /// @param amount Amount to burn
    /// @param poolManager Reference to the `PoolManager` contract for which the `stocksUsers` will need to be updated
    function burnFromNoRedeem(
        address account,
        uint256 amount,
        address poolManager
    ) external {
        _burnFromNoRedeem(amount, account, msg.sender);
        IStableMaster(stableMaster).updateStocksUsers(amount, poolManager);
    }

    // ======================= Minter Role Only Functions ==========================

    /// @notice Burns `amount` tokens from a `burner` address
    /// @param amount Amount of tokens to burn
    /// @param burner Address to burn from
    /// @dev This method is to be called by a contract with a minter right on the AgToken after being
    /// requested to do so by an address willing to burn tokens from its address
    function burnSelf(uint256 amount, address burner) external onlyMinter {
        _burn(burner, amount);
    }

    /// @notice Burns `amount` tokens from a `burner` address after being asked to by `sender`
    /// @param amount Amount of tokens to burn
    /// @param burner Address to burn from
    /// @param sender Address which requested the burn from `burner`
    /// @dev This method is to be called by a contract with the minter right after being requested
    /// to do so by a `sender` address willing to burn tokens from another `burner` address
    /// @dev The method checks the allowance between the `sender` and the `burner`
    function burnFrom(
        uint256 amount,
        address burner,
        address sender
    ) external onlyMinter {
        _burnFromNoRedeem(amount, burner, sender);
    }

    /// @notice Lets the `StableMaster` contract or another whitelisted contract mint agTokens
    /// @param account Address to mint to
    /// @param amount Amount to mint
    /// @dev The contracts allowed to issue agTokens are the `StableMaster` contract, `VaultManager` contracts
    /// associated to this stablecoin as well as the flash loan module (if activated) and potentially contracts
    /// whitelisted by governance
    function mint(address account, uint256 amount) external onlyMinter {
        _mint(account, amount);
    }

    // ======================= Minter Only Functions ===============================

    /// @notice Adds a minter in the contract
    /// @param minter Minter address to add
    function addMinter(address minter) external onlyMinter {
        isMinter[minter] = true;
        emit MinterToggled(minter);
    }

    /// @notice Removes a minter from the contract
    /// @param minter Minter address to remove
    /// @dev This function can at the moment only be called by a minter wishing to revoke itself
    function removeMinter(address minter) external {
        require(msg.sender == minter && isMinter[msg.sender], "36");
        isMinter[minter] = false;
        emit MinterToggled(minter);
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
            require(currentAllowance >= amount, "23");
            _approve(burner, sender, currentAllowance - amount);
        }
        _burn(burner, amount);
    }
}
