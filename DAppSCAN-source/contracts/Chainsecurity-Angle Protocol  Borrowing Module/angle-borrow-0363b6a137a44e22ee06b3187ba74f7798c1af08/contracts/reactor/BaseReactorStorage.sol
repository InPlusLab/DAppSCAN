// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "../interfaces/external/IERC4626.sol";
import "../interfaces/IVaultManager.sol";

/// @title BaseReactorStorage
/// @author Angle Core Team
/// @dev Variables, references, parameters and events needed in the `BaseReactor` contract
// solhint-disable-next-line max-states-count
contract BaseReactorStorage is Initializable, ReentrancyGuardUpgradeable {
    /// @notice Base used for parameter computation
    uint256 public constant BASE_PARAMS = 10**9;

    // =============================== References ==================================

    /// @notice Reference to the asset controlled by this reactor
    IERC20 public asset;
    /// @notice Reference to the stablecoin this reactor handles
    IAgToken public stablecoin;
    /// @notice Oracle giving the price of the asset with respect to the stablecoin
    IOracle public oracle;
    /// @notice Treasury contract handling access control
    ITreasury public treasury;
    /// @notice VaultManager contract on which this contract has a vault. All references should
    /// be fetched from here
    IVaultManager public vaultManager;
    /// @notice ID of the vault handled by this contract
    uint256 public vaultID;
    /// @notice Dust parameter for the stablecoins in a vault in `VaultManager`
    uint256 public vaultManagerDust;
    /// @notice Base of the `asset`. While it is assumed in this contract that the base of the stablecoin is 18,
    /// the base of the `asset` may not be 18
    uint256 internal _assetBase;

    // =============================== Parameters ==================================

    /// @notice Lower value of the collateral factor: below this the reactor can borrow stablecoins
    uint64 public lowerCF;
    /// @notice Value of the collateral factor targeted by this vault
    uint64 public targetCF;
    /// @notice Value of the collateral factor above which stablecoins should be repaid to avoid liquidations
    uint64 public upperCF;
    /// @notice Value of the fees going to the protocol at each yield gain from the strategy
    uint64 public protocolInterestShare;
    /// @notice Address responsible for handling the surplus of the protocol
    address public surplusManager;

    // =============================== Variables ===================================

    /// @notice Protocol fee surplus: the protocol should only accumulate yield from the strategies and not make a gain
    /// in situations where there are liquidations or so.
    uint256 public protocolInterestAccumulated;
    /// @notice Loss accumulated to be taken from the protocol
    uint256 public protocolDebt;
    /// @notice Rewards (in stablecoin) claimable by depositors of the reactor
    uint256 public claimableRewards;
    /// @notice Loss (in stablecoin) accumulated by the reactor: it's going to prevent the reactor from
    /// repaying its debt
    uint256 public currentLoss;
    /// @notice Used to track rewards accumulated by all depositors of the reactor
    uint256 public rewardsAccumulator;
    /// @notice Tracks rewards already claimed by all depositors
    uint256 public claimedRewardsAccumulator;
    /// @notice Last time rewards were claimed in the reactor
    uint256 public lastTime;
    /// @notice Last known stable debt to the `VaultManager`
    uint256 public lastDebt;

    /// @notice Maps an address to the last time it claimed its rewards
    mapping(address => uint256) public lastTimeOf;
    /// @notice Maps an address to a quantity depending on time and shares of the reactors used
    /// to compute the rewards an address can claim
    mapping(address => uint256) public rewardsAccumulatorOf;

    uint256[50] private __gap;

    // =============================== Events ======================================

    event FiledUint64(uint64 param, bytes32 what);
    event Recovered(address indexed token, address indexed to, uint256 amount);

    // =============================== Errors ======================================

    error InvalidParameterValue();
    error InvalidParameterType();
    error InvalidSetOfParameters();
    error InvalidToken();
    error NotGovernor();
    error NotGovernorOrGuardian();
    error NotVaultManager();
    error TooHighParameterValue();
    error TransferAmountExceedsAllowance();
    error ZeroAddress();
    error ZeroAssets();
    error ZeroShares();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}
}
