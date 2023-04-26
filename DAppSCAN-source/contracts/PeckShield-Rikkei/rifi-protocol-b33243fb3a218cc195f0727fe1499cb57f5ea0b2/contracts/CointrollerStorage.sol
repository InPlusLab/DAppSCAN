pragma solidity ^0.5.16;

import "./RToken.sol";
import "./PriceOracle.sol";

contract UnitrollerAdminStorage {
    /**
     * @notice Administrator for this contract
     */
    address public admin;

    /**
     * @notice Pending administrator for this contract
     */
    address public pendingAdmin;

    /**
     * @notice Active brains of Unitroller
     */
    address public cointrollerImplementation;

    /**
     * @notice Pending brains of Unitroller
     */
    address public pendingCointrollerImplementation;
}

contract CointrollerStorage is UnitrollerAdminStorage {
    /**
     * @notice Oracle which gives the price of any given asset
     */
    PriceOracle public oracle;

    /**
     * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
     */
    uint256 public closeFactorMantissa;

    /**
     * @notice Multiplier representing the discount on collateral that a liquidator receives
     */
    uint256 public liquidationIncentiveMantissa;

    /**
     * @notice Max number of assets a single account can participate in (borrow or use as collateral)
     */
    uint256 public maxAssets;

    /**
     * @notice Per-account mapping of "assets you are in", capped by maxAssets
     */
    mapping(address => RToken[]) public accountAssets;

    struct Market {
        /// @notice Whether or not this market is listed
        bool isListed;
        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        uint256 collateralFactorMantissa;
        /// @notice Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
        /// @notice Whether or not this market receives RIFI
        bool isRified;
    }

    /**
     * @notice Official mapping of rTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    mapping(address => Market) public markets;

    /**
     * @notice The Pause Guardian can pause certain actions as a safety mechanism.
     *  Actions which allow users to remove their own assets cannot be paused.
     *  Liquidation / seizing / transfer can only be paused globally, not by market.
     */
    address public pauseGuardian;
    bool public _mintGuardianPaused;
    bool public _borrowGuardianPaused;
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    mapping(address => bool) public mintGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;

    struct RifiMarketState {
        /// @notice The market's last updated rifiBorrowIndex or rifiSupplyIndex
        uint224 index;
        /// @notice The block number the index was last updated at
        uint32 block;
    }

    /// @notice A list of all markets
    RToken[] public allMarkets;

    /// @notice The rate at which the flywheel distributes RIFI, per block
    uint256 public rifiRate;

    /// @notice The portion of rifiRate that each market currently receives
    mapping(address => uint256) public rifiSpeeds;

    /// @notice The RIFI market supply state for each market
    mapping(address => RifiMarketState) public rifiSupplyState;

    /// @notice The RIFI market borrow state for each market
    mapping(address => RifiMarketState) public rifiBorrowState;

    /// @notice The RIFI borrow index for each market for each supplier as of the last time they accrued RIFI
    mapping(address => mapping(address => uint256)) public rifiSupplierIndex;

    /// @notice The RIFI borrow index for each market for each borrower as of the last time they accrued RIFI
    mapping(address => mapping(address => uint256)) public rifiBorrowerIndex;

    /// @notice The RIFI accrued but not yet transferred to each user
    mapping(address => uint256) public rifiAccrued;

    // @notice The borrowCapGuardian can set borrowCaps to any number for any market. Lowering the borrow cap could disable borrowing on the given market.
    address public borrowCapGuardian;

    // @notice Borrow caps enforced by borrowAllowed for each rToken address. Defaults to zero which corresponds to unlimited borrowing.
    mapping(address => uint256) public borrowCaps;

    /// @notice The portion of RIFI that each contributor receives per block
    mapping(address => uint256) public rifiContributorSpeeds;

    /// @notice Last block at which a contributor's RIFI rewards have been allocated
    mapping(address => uint256) public lastContributorBlock;
}
