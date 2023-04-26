// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "./utils/ERC20UpgradeableCustom.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/IAgToken.sol";
import "../../interfaces/ITreasury.sol";

interface IChildToken {
    function deposit(address user, bytes calldata depositData) external;

    function withdraw(uint256 amount) external;
}

contract TokenPolygonUpgradeable is
    Initializable,
    ERC20UpgradeableCustom,
    AccessControlUpgradeable,
    EIP712Upgradeable,
    IChildToken
{
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    /// @dev emitted when the child chain manager changes
    event ChildChainManagerAdded(address newAddress);
    event ChildChainManagerRevoked(address oldAddress);

    constructor() initializer {}

    function initialize(
        string memory _name,
        string memory _symbol,
        address childChainManager,
        address guardian
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, guardian);
        _setupRole(DEPOSITOR_ROLE, childChainManager);
        __EIP712_init(_name, "1");
    }

    /**
     * @notice called when the bridge has tokens to mint
     * @param user address to mint the token to
     * @param depositData encoded amount to mint
     */
    function deposit(address user, bytes calldata depositData) external override {
        require(hasRole(DEPOSITOR_ROLE, msg.sender));
        uint256 amount = abi.decode(depositData, (uint256));
        _mint(user, amount);
    }

    /**
     * @notice called when user wants to withdraw tokens back to root chain
     * @dev Should burn user's tokens. This transaction will be verified when exiting on root chain
     * @param amount amount of tokens to withdraw
     */
    function withdraw(uint256 amount) external override {
        _burn(_msgSender(), amount);
    }

    // =============================================================================
    // ======================= New data added for the upgrade ======================
    // =============================================================================

    mapping(address => bool) public isMinter;
    /// @notice Reference to the treasury contract which can grant minting rights
    address public treasury;
    /// @notice Boolean to check whether the contract has been reinitialized after its upgrade
    bool public treasuryInitialized;

    using SafeERC20 for IERC20;

    /// @notice Base used for fee computation
    uint256 public constant BASE_PARAMS = 10**9;

    // =============================== Bridging Data ===============================

    /// @notice Struct with some data about a specific bridge token
    struct BridgeDetails {
        // Whether the associated token is allowed or not
        bool allowed;
        // Whether swapping in and out from the associated token is paused or not
        bool paused;
        // Limit on the balance of bridge token held by the contract: it is designed
        // to reduce the exposure of the system to hacks
        uint256 limit;
        // Fee taken for swapping in and out the token
        uint64 fee;
    }

    /// @notice Maps a bridge token to data
    mapping(address => BridgeDetails) public bridges;
    /// @notice List of all bridge tokens
    address[] public bridgeTokensList;
    /// @notice Maps an address to whether it is exempt of fees for when it comes to swapping in and out
    mapping(address => bool) public isFeeExempt;

    // ================================== Events ===================================

    event BridgeTokenAdded(address indexed bridgeToken, uint256 limit, uint64 fee, bool paused);
    event BridgeTokenToggled(address indexed bridgeToken, bool toggleStatus);
    event BridgeTokenRemoved(address indexed bridgeToken);
    event BridgeTokenFeeUpdated(address indexed bridgeToken, uint64 fee);
    event BridgeTokenLimitUpdated(address indexed bridgeToken, uint256 limit);
    event Recovered(address indexed token, address indexed to, uint256 amount);
    event FeeToggled(address indexed theAddress, bool toggleStatus);
    event TreasuryUpdated(address indexed _treasury);
    event MinterToggled(address indexed minter);

    // ================================== Errors ===================================

    error AssetStillControlledInReserves();
    error BurnAmountExceedsAllowance();
    error InvalidSender();
    error InvalidToken();
    error InvalidTreasury();
    error NotGovernor();
    error NotGovernorOrGuardian();
    error NotMinter();
    error NotTreasury();
    error TooBigAmount();
    error TooHighParameterValue();
    error TreasuryAlreadyInitialized();

    /// @notice Checks to see if it is the `Treasury` calling this contract
    /// @dev There is no Access Control here, because it can be handled cheaply through this modifier
    modifier onlyTreasury() {
        if (msg.sender != treasury) revert NotTreasury();
        _;
    }

    /// @notice Checks whether the sender has the minting right
    modifier onlyMinter() {
        if (!isMinter[msg.sender]) revert NotMinter();
        _;
    }

    /// @notice Checks whether the `msg.sender` has the governor role or not
    modifier onlyGovernor() {
        if (!ITreasury(treasury).isGovernor(msg.sender)) revert NotGovernor();
        _;
    }

    /// @notice Checks whether the `msg.sender` has the governor role or the guardian role
    modifier onlyGovernorOrGuardian() {
        if (!ITreasury(treasury).isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        _;
    }

    /// @notice Sets up the treasury contract on Polygon after the upgrade
    /// @param _treasury Address of the treasury contract
    function setUpTreasury(address _treasury) external {
        // Only governor on Polygon
        if (msg.sender != 0xdA2D2f638D6fcbE306236583845e5822554c02EA) revert NotGovernor();
        if (address(ITreasury(_treasury).stablecoin()) != address(this)) revert InvalidTreasury();
        if (treasuryInitialized) revert TreasuryAlreadyInitialized();
        treasury = _treasury;
        treasuryInitialized = true;
        emit TreasuryUpdated(_treasury);
    }

    // =========================== External Function ===============================

    /// @notice Allows anyone to burn agToken without redeeming collateral back
    /// @param amount Amount of stablecoins to burn
    /// @dev This function can typically be called if there is a settlement mechanism to burn stablecoins
    function burnStablecoin(uint256 amount) external {
        _burnCustom(msg.sender, amount);
    }

    // ======================= Minter Role Only Functions ==========================

    function burnSelf(uint256 amount, address burner) external onlyMinter {
        _burnCustom(burner, amount);
    }

    function burnFrom(
        uint256 amount,
        address burner,
        address sender
    ) external onlyMinter {
        _burnFromNoRedeem(amount, burner, sender);
    }

    function mint(address account, uint256 amount) external onlyMinter {
        _mint(account, amount);
    }

    // ======================= Treasury Only Functions =============================

    function addMinter(address minter) external onlyTreasury {
        isMinter[minter] = true;
        emit MinterToggled(minter);
    }

    function removeMinter(address minter) external {
        if (msg.sender != address(treasury) && msg.sender != minter) revert InvalidSender();
        isMinter[minter] = false;
        emit MinterToggled(minter);
    }

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
        _burnCustom(burner, amount);
    }

    // ==================== External Permissionless Functions ======================

    /// @notice Returns the list of all supported bridge tokens
    /// @dev Helpful for UIs
    function allBridgeTokens() external view returns (address[] memory) {
        return bridgeTokensList;
    }

    /// @notice Mints the canonical token from a supported bridge token
    /// @param bridgeToken Bridge token to use to mint
    /// @param amount Amount of bridge tokens to send
    /// @param to Address to which the stablecoin should be sent
    /// @dev Some fees may be taken by the protocol depending on the token used and on the address calling
    function swapIn(
        address bridgeToken,
        uint256 amount,
        address to
    ) external {
        BridgeDetails memory bridgeDetails = bridges[bridgeToken];
        if (!bridgeDetails.allowed || bridgeDetails.paused) revert InvalidToken();
        if (IERC20(bridgeToken).balanceOf(address(this)) + amount > bridgeDetails.limit) revert TooBigAmount();
        IERC20(bridgeToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 canonicalOut = amount;
        // Computing fees
        if (!isFeeExempt[msg.sender]) {
            canonicalOut -= (canonicalOut * bridgeDetails.fee) / BASE_PARAMS;
        }
        _mint(to, canonicalOut);
    }

    /// @notice Burns the canonical token in exchange for a bridge token
    /// @param bridgeToken Bridge token required
    /// @param amount Amount of canonical tokens to burn
    /// @param to Address to which the bridge token should be sent
    /// @dev Some fees may be taken by the protocol depending on the token used and on the address calling
    function swapOut(
        address bridgeToken,
        uint256 amount,
        address to
    ) external {
        BridgeDetails memory bridgeDetails = bridges[bridgeToken];
        if (!bridgeDetails.allowed || bridgeDetails.paused) revert InvalidToken();
        _burnCustom(msg.sender, amount);
        uint256 bridgeOut = amount;
        if (!isFeeExempt[msg.sender]) {
            bridgeOut -= (bridgeOut * bridgeDetails.fee) / BASE_PARAMS;
        }
        IERC20(bridgeToken).safeTransfer(to, bridgeOut);
    }

    // ======================= Governance Functions ================================

    /// @notice Adds support for a bridge token
    /// @param bridgeToken Bridge token to add: it should be a version of the stablecoin from another bridge
    /// @param limit Limit on the balance of bridge token this contract could hold
    /// @param paused Whether swapping for this token should be paused or not
    /// @param fee Fee taken upon swapping for or against this token
    function addBridgeToken(
        address bridgeToken,
        uint256 limit,
        uint64 fee,
        bool paused
    ) external onlyGovernor {
        if (bridges[bridgeToken].allowed || bridgeToken == address(0)) revert InvalidToken();
        if (fee > BASE_PARAMS) revert TooHighParameterValue();
        BridgeDetails memory _bridge;
        _bridge.limit = limit;
        _bridge.paused = paused;
        _bridge.fee = fee;
        _bridge.allowed = true;
        bridges[bridgeToken] = _bridge;
        bridgeTokensList.push(bridgeToken);
        emit BridgeTokenAdded(bridgeToken, limit, fee, paused);
    }

    /// @notice Removes support for a token
    /// @param bridgeToken Address of the bridge token to remove support for
    function removeBridgeToken(address bridgeToken) external onlyGovernor {
        if (IERC20(bridgeToken).balanceOf(address(this)) != 0) revert AssetStillControlledInReserves();
        delete bridges[bridgeToken];
        // Deletion from `bridgeTokensList` loop
        uint256 bridgeTokensListLength = bridgeTokensList.length;
        for (uint256 i = 0; i < bridgeTokensListLength - 1; i++) {
            if (bridgeTokensList[i] == bridgeToken) {
                // Replace the `bridgeToken` to remove with the last of the list
                bridgeTokensList[i] = bridgeTokensList[bridgeTokensListLength - 1];
                break;
            }
        }
        // Remove last element in array
        bridgeTokensList.pop();
        emit BridgeTokenRemoved(bridgeToken);
    }

    /// @notice Recovers any ERC20 token
    /// @dev Can be used to withdraw bridge tokens for them to be de-bridged on mainnet
    function recoverERC20(
        address tokenAddress,
        address to,
        uint256 amountToRecover
    ) external onlyGovernor {
        IERC20(tokenAddress).safeTransfer(to, amountToRecover);
        emit Recovered(tokenAddress, to, amountToRecover);
    }

    /// @notice Updates the `limit` amount for `bridgeToken`
    function setLimit(address bridgeToken, uint256 limit) external onlyGovernorOrGuardian {
        if (!bridges[bridgeToken].allowed) revert InvalidToken();
        bridges[bridgeToken].limit = limit;
        emit BridgeTokenLimitUpdated(bridgeToken, limit);
    }

    /// @notice Updates the `fee` value for `bridgeToken`
    function setSwapFee(address bridgeToken, uint64 fee) external onlyGovernorOrGuardian {
        if (!bridges[bridgeToken].allowed) revert InvalidToken();
        if (fee > BASE_PARAMS) revert TooHighParameterValue();
        bridges[bridgeToken].fee = fee;
        emit BridgeTokenFeeUpdated(bridgeToken, fee);
    }

    /// @notice Pauses or unpauses swapping in and out for a token
    function toggleBridge(address bridgeToken) external onlyGovernorOrGuardian {
        if (!bridges[bridgeToken].allowed) revert InvalidToken();
        bool pausedStatus = bridges[bridgeToken].paused;
        bridges[bridgeToken].paused = !pausedStatus;
        emit BridgeTokenToggled(bridgeToken, !pausedStatus);
    }

    /// @notice Toggles fees for the address `theAddress`
    function toggleFeesForAddress(address theAddress) external onlyGovernorOrGuardian {
        bool feeExemptStatus = isFeeExempt[theAddress];
        isFeeExempt[theAddress] = !feeExemptStatus;
        emit FeeToggled(theAddress, !feeExemptStatus);
    }

    uint256[49] private __gap;
}
