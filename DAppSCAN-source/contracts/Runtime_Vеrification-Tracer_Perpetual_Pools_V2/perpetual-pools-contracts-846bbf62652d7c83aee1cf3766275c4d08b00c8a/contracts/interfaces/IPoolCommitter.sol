//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity 0.8.7;

/// @title The interface for the contract that handles pool commitments
interface IPoolCommitter {
    /// Type of commit
    enum CommitType {
        ShortMint, // Mint short tokens
        ShortBurn, // Burn short tokens
        LongMint, // Mint long tokens
        LongBurn, // Burn long tokens
        LongBurnShortMint, // Burn Long tokens, then instantly mint in same upkeep
        ShortBurnLongMint // Burn Short tokens, then instantly mint in same upkeep
    }

    struct BalancesAndSupplies {
        uint256 shortBalance;
        uint256 longBalance;
        uint256 longTotalSupplyBefore;
        uint256 shortTotalSupplyBefore;
    }

    // User aggregate balance
    struct Balance {
        uint256 longTokens;
        uint256 shortTokens;
        uint256 settlementTokens;
    }

    // Token Prices
    struct Prices {
        bytes16 longPrice;
        bytes16 shortPrice;
    }

    // Commit information
    struct Commit {
        uint256 amount;
        CommitType commitType;
        uint40 created;
        address owner;
    }

    // Commit information
    struct TotalCommitment {
        uint256 longMintAmount;
        uint256 longBurnAmount;
        uint256 shortMintAmount;
        uint256 shortBurnAmount;
        uint256 shortBurnLongMintAmount;
        uint256 longBurnShortMintAmount;
        uint256 updateIntervalId;
    }

    struct BalanceUpdate {
        uint256 _updateIntervalId;
        uint256 _newLongTokensSum;
        uint256 _newShortTokensSum;
        uint256 _newSettlementTokensSum;
        uint256 _balanceLongBurnAmount;
        uint256 _balanceShortBurnAmount;
    }

    // Track how much of a user's commitments are being done from their aggregate balance
    struct UserCommitment {
        uint256 longMintAmount;
        uint256 longBurnAmount;
        uint256 balanceLongBurnAmount;
        uint256 shortMintAmount;
        uint256 shortBurnAmount;
        uint256 balanceShortBurnAmount;
        uint256 shortBurnLongMintAmount;
        uint256 balanceShortBurnMintAmount;
        uint256 longBurnShortMintAmount;
        uint256 balanceLongBurnMintAmount;
        uint256 updateIntervalId;
    }

    /**
     * @notice Creates a notification when a commit is created
     * @param user The user making the commitment
     * @param amount Amount of the commit
     * @param commitType Type of the commit (Short v Long, Mint v Burn)
     */
    event CreateCommit(address indexed user, uint256 indexed amount, CommitType indexed commitType);

    /**
     * @notice Creates a notification when a user's aggregate balance is updated
     */
    event AggregateBalanceUpdated(address indexed user);

    /**
     * @notice Creates a notification when a claim is made, depositing pool tokens in user's wallet
     */
    event Claim(address indexed user);

    // #### Functions

    function initialize(address _factory) external;

    function commit(
        CommitType commitType,
        uint256 amount,
        bool fromAggregateBalance
    ) external;

    function claim(address user) external;

    function executeCommitments() external;

    function updateAggregateBalance(address user) external;

    function getAggregateBalance(address user) external view returns (Balance memory _balance);

    function setQuoteAndPool(address quoteToken, address leveragedPool) external;
}
