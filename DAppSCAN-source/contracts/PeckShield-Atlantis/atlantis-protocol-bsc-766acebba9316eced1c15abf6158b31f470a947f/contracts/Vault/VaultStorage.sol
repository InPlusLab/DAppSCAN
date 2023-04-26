pragma solidity ^0.5.16;
import "../SafeMath.sol";
import "./Utils/IBEP20.sol";

contract VaultAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of Vault
    */
    address public vaultImplementation;

    /**
    * @notice Pending brains of Vault
    */
    address public pendingVaultImplementation;
}

contract VaultStorage is VaultAdminStorage {
    /// @notice The Vault Token
    IBEP20 public stakedToken;

    /// @notice The Atlantis store
    address public atlantisStore;

    /// @notice Guard variable for re-entrancy checks
    bool internal _notEntered;

    /// @notice Atlantis balance inside the vault store
    uint256 public atlantisBalance;

    /// @notice Accumulated Atlantis per share
    uint256 public accAtlantisPerShare;

    /// @notice pending rewards awaiting anyone to update
    uint256 public pendingRewards;

    /// @notice Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    // Info of each user that stakes tokens.
    mapping(address => UserInfo) public userInfo;
}
