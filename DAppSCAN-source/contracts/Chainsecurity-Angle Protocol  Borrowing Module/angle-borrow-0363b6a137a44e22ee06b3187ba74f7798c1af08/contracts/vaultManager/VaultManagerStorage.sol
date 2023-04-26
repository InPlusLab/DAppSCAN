// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC721MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IAgToken.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ISwapper.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/governance/IVeBoostProxy.sol";

/// @title VaultManagerStorage
/// @author Angle Core Team
/// @dev Variables, references, parameters and events needed in the `VaultManager` contract
// solhint-disable-next-line max-states-count
contract VaultManagerStorage is IVaultManagerStorage, Initializable, ReentrancyGuardUpgradeable {
    /// @notice Base used for parameter computation: almost all the parameters of this contract are set in `BASE_PARAMS`
    uint256 public constant BASE_PARAMS = 10**9;
    /// @notice Base used for interest rate computation
    uint256 public constant BASE_INTEREST = 10**27;
    /// @notice Used for interest rate computation
    uint256 public constant HALF_BASE_INTEREST = 10**27 / 2;

    // =============================== References ==================================

    /// @inheritdoc IVaultManagerStorage
    ITreasury public treasury;
    /// @inheritdoc IVaultManagerStorage
    IERC20 public collateral;
    /// @inheritdoc IVaultManagerStorage
    IAgToken public stablecoin;
    /// @inheritdoc IVaultManagerStorage
    IOracle public oracle;
    /// @notice Reference to the contract which computes adjusted veANGLE balances for liquidators boosts
    IVeBoostProxy public veBoostProxy;
    /// @notice Base of the collateral
    uint256 internal _collatBase;

    // =============================== Parameters ==================================
    // Unless specified otherwise, parameters of this contract are expressed in `BASE_PARAMS`

    /// @inheritdoc IVaultManagerStorage
    uint256 public immutable dust;
    /// @notice Minimum amount of collateral (in stablecoin value, e.g in `BASE_TOKENS = 10**18`) that can be left
    ///  in a vault during a liquidation where the health factor function is decreasing
    uint256 internal immutable _dustCollateral;
    /// @notice Maximum amount of stablecoins that can be issued with this contract (in `BASE_TOKENS`). This parameter should
    /// not be bigger than `type(uint256).max / BASE_INTEREST` otherwise there may be some overflows in the `increaseDebt` function
    uint256 public debtCeiling;
    /// @notice Threshold veANGLE balance values for the computation of the boost for liquidators: the length of this array
    /// should normally be 2. The base of the x-values in this array should be `BASE_TOKENS`
    uint256[] public xLiquidationBoost;
    /// @notice Values of the liquidation boost at the threshold values of x
    uint256[] public yLiquidationBoost;
    /// @inheritdoc IVaultManagerStorage
    uint64 public collateralFactor;
    /// @notice Maximum Health factor at which a vault can end up after a liquidation (unless it's fully liquidated)
    uint64 public targetHealthFactor;
    /// @notice Upfront fee taken when borrowing stablecoins: this fee is optional and should in practice not be used
    uint64 public borrowFee;
    /// @notice Upfront fee taken when repaying stablecoins: this fee is optional as well. It should be smaller
    /// than the liquidation surcharge (cf below) to avoid exploits where people voluntarily get liquidated at a 0
    /// discount to pay smaller repaying fees
    uint64 public repayFee;
    /// @notice Per second interest taken to borrowers taking agToken loans. Contrarily to other parameters, it is set in `BASE_INTEREST`
    /// that is to say in base 10**27
    uint64 public interestRate;
    /// @notice Fee taken by the protocol during a liquidation. Technically, this value is not the fee per se, it's 1 - fee.
    /// For instance for a 2% fee, `liquidationSurcharge` should be 98%
    uint64 public liquidationSurcharge;
    /// @notice Maximum discount given to liquidators
    uint64 public maxLiquidationDiscount;
    /// @notice Whether whitelisting is required to own a vault or not
    bool public whitelistingActivated;
    /// @notice Whether the contract is paused or not
    bool public paused;

    // =============================== Variables ===================================

    /// @notice Timestamp at which the `interestAccumulator` was updated
    uint256 public lastInterestAccumulatorUpdated;
    /// @inheritdoc IVaultManagerStorage
    uint256 public interestAccumulator;
    /// @inheritdoc IVaultManagerStorage
    uint256 public totalNormalizedDebt;
    /// @notice Surplus accumulated by the contract: surplus is always in stablecoins, and is then reset
    /// when the value is communicated to the treasury contract
    uint256 public surplus;
    /// @notice Bad debt made from liquidated vaults which ended up having no collateral and a positive amount
    /// of stablecoins
    uint256 public badDebt;

    // ================================ Mappings ===================================

    /// @inheritdoc IVaultManagerStorage
    mapping(uint256 => Vault) public vaultData;
    /// @notice Maps an address to 1 if it's whitelisted and can open or own a vault
    mapping(address => uint256) public isWhitelisted;

    // ================================ ERC721 Data ================================

    /// @inheritdoc IVaultManagerStorage
    uint256 public vaultIDCount;

    /// @notice URI
    string internal _baseURI;

    // Mapping from `vaultID` to owner address
    mapping(uint256 => address) internal _owners;

    // Mapping from owner address to vault owned count
    mapping(address => uint256) internal _balances;

    // Mapping from `vaultID` to approved address
    mapping(uint256 => address) internal _vaultApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => uint256)) internal _operatorApprovals;

    uint256[50] private __gap;

    // =============================== Events ======================================

    event AccruedToTreasury(uint256 surplusEndValue, uint256 badDebtEndValue);
    event CollateralAmountUpdated(uint256 vaultID, uint256 collateralAmount, uint8 isIncrease);
    event InterestAccumulatorUpdated(uint256 value, uint256 timestamp);
    event InternalDebtUpdated(uint256 vaultID, uint256 internalAmount, uint8 isIncrease);
    event FiledUint64(uint64 param, bytes32 what);
    event DebtCeilingUpdated(uint256 debtCeiling);
    event LiquidationBoostParametersUpdated(address indexed _veBoostProxy, uint256[] xBoost, uint256[] yBoost);
    event LiquidatedVaults(uint256[] vaultIDs);
    event DebtTransferred(uint256 srcVaultID, uint256 dstVaultID, address dstVaultManager, uint256 amount);

    // =============================== Errors ======================================

    error ApprovalToOwner();
    error ApprovalToCaller();
    error DustyLeftoverAmount();
    error DebtCeilingExceeded();
    error HealthyVault();
    error IncompatibleLengths();
    error InsolventVault();
    error InvalidParameterValue();
    error InvalidParameterType();
    error InvalidSetOfParameters();
    error InvalidTreasury();
    error NonERC721Receiver();
    error NonexistentVault();
    error NotApproved();
    error NotGovernor();
    error NotGovernorOrGuardian();
    error NotTreasury();
    error NotWhitelisted();
    error NotVaultManager();
    error Paused();
    error TooHighParameterValue();
    error TooSmallParameterValue();
    error ZeroAddress();

    /// @param _dust Minimum amount of debt a vault from this implementation can have
    /// @param dustCollateral_ Minimum amount of collateral (in stablecoin value) that can be left in a vault during a liquidation
    /// where the health factor function is decreasing
    /// @dev Run only at the implementation level
    constructor(uint256 _dust, uint256 dustCollateral_) initializer {
        dust = _dust;
        _dustCollateral = dustCollateral_;
    }
}
