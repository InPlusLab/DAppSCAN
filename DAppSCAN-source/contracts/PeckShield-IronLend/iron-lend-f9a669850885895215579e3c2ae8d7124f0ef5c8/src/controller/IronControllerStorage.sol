pragma solidity ^0.5.16;

import "../RToken/RToken.sol";
import "../interfaces/PriceOracle.sol";
import "./IronDelegateControllerAdminStorage.sol";

contract IronControllerStorage is IronDelegateControllerAdminStorage {
    struct RewardMarketState {
        /// @notice The market's last updated rewardBorrowIndex or rewardSupplyIndex
        uint224 index;

        /// @notice The block number the index was last updated at
        uint32 block;
    }

    struct Market {
        /// @notice Whether or not this market is listed
        bool isListed;

        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        uint collateralFactorMantissa;

        /// @notice Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
    }

    /**
     * @notice Oracle which gives the price of any given asset
     */
    PriceOracle public oracle;

    /**
     * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
     */
    uint public closeFactorMantissa;

    /**
     * @notice Multiplier representing the discount on collateral that a liquidator receives
     */
    uint public liquidationIncentiveMantissa;

    /**
     * @notice Max number of assets a single account can participate in (borrow or use as collateral)
     */
    uint public maxAssets;

    /**
     * @notice Per-account mapping of "assets you are in", capped by maxAssets
     */
    mapping(address => RToken[]) public accountAssets;

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
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    mapping(address => bool) public mintGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;

    /// @notice A list of all markets
    RToken[] public allMarkets;

    /// @notice The portion of rewardRate that each market currently receives
    mapping(address => uint) public rewardSpeeds;

    /// @notice The REWARD market supply state for each market
    mapping(address => RewardMarketState) public rewardSupplyState;

    /// @notice The REWARD market borrow state for each market
    mapping(address => RewardMarketState) public rewardBorrowState;

    /// @notice The REWARD borrow index for each market for each supplier as of the last time they accrued REWARD
    mapping(address => mapping(address => uint)) public rewardSupplierIndex;

    /// @notice The REWARD borrow index for each market for each borrower as of the last time they accrued REWARD
    mapping(address => mapping(address => uint)) public rewardBorrowerIndex;

    /// @notice The REWARD accrued but not yet transferred to each user
    mapping(address => uint) public rewardAccrued;

    // @notice The borrowCapGuardian can set borrowCaps to any number for any market. Lowering the borrow cap could disable borrowing on the given market.
    address public borrowCapGuardian;

    // @notice Borrow caps enforced by borrowAllowed for each rToken address. Defaults to zero which corresponds to unlimited borrowing.
    mapping(address => uint) public borrowCaps;
}
