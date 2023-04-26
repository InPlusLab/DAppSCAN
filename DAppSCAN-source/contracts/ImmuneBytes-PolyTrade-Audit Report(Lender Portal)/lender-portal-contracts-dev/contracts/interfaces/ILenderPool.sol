//SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

interface ILenderPool {
    struct Round {
        bool paidTrade;
        uint16 stableAPY;
        uint16 bonusAPY;
        uint48 startPeriod;
        uint48 endPeriod;
        uint amountLent;
    }

    struct LenderInfo {
        uint amountLent;
        uint roundCount;
    }

    /**
     * @notice changes the minimum amount required for deposit (newRound)
     * @dev update `minimumDeposit` with `newMinimumDeposit`
     * @param newMinimumDeposit, new amount for minimum deposit
     */
    function setMinimumDeposit(uint newMinimumDeposit) external;

    /**
     * @notice create new Round on behalf of the lender, each deposit has its own round
     * @dev `lender` must approve the amount to be deposited first
     * @dev only `Owner` can launch a new round
     * @dev add new round to `_lenderRounds`
     * @dev `amount` will be transferred from `lender` to `address(this)`
     * @dev emits Deposit event
     * @param lender, address of the lender
     * @param amount, amount to be deposited by the lender, must be greater than minimumDeposit
     * @param bonusAPY, bonus ratio to be applied
     * @param paidTrade, specifies whether if stable rewards will be paid in Trade(true) or in stable(false)
     */
    function newRound(
        address lender,
        uint amount,
        uint16 bonusAPY,
        bool paidTrade
    ) external;

    /**
     * @notice transfer tokens from the contract to the treasury
     * @dev only `Owner` can send to treasury
     * @param tokenAddress address of the token to be transferred
     * @param amount amount of tokens to be transferred
     */
    function sendToTreasury(address tokenAddress, uint amount) external;

    /**
     * @notice Withdraw the initial deposit of the specified lender for the specified roundId
     * @notice claim rewards of the specified roundId for the specific lender
     * @dev only `Owner` can withdraw
     * @dev round must be finish (`block.timestamp` must be higher than `round.endPeriod`)
     * @dev run `_claimRewards` and `_withdraw`
     * @param lender, address of the lender
     * @param roundId, Id of the round
     * @param amountOutMin, The minimum amount tokens to receive
     */
    function withdraw(
        address lender,
        uint roundId,
        uint amountOutMin
    ) external;

    /**
     * @notice Returns all the information of a specific round for a specific lender
     * @dev returns Round struct of the specific round for a specific lender
     * @param lender, address of the lender to be checked
     * @param roundId, Id of the round to be checked
     * @return Round ({ bool paidTrade, uint16 bonusAPY, uint amountLent, uint64 startPeriod, uint64 endPeriod })
     */
    function getRound(address lender, uint roundId)
        external
        view
        returns (Round memory);

    /**
     * @notice Returns the latest round for a specific lender
     * @param lender, address of the lender to be checked
     * @return returns the latest round for a specific Lender
     */
    function getLatestRound(address lender) external view returns (uint);

    /**
     * @notice Returns the total amount lent for the lender on every round
     * @param lender, address of the lender to be checked
     * @return returns amount lent by a lender
     */
    function getAmountLent(address lender) external view returns (uint);

    /**
     * @notice Returns roundIds of every finished round
     * @param lender, address of the lender to be checked
     * @return returns array with all finished round Ids
     */
    function getFinishedRounds(address lender)
        external
        view
        returns (uint[] memory);

    /**
     * @notice Returns the amount of stable rewards for a specific lender on a specific roundId
     * @dev run `_calculateRewards` with `_stableAPY` based on the amountLent
     * @param lender, address of the lender to be checked
     * @param roundId, Id of the round to be checked
     * @return returns the amount of stable rewards (based on stableInstance)
     */
    function stableRewardOf(address lender, uint roundId)
        external
        view
        returns (uint);

    /**
     * @notice Returns the amount of bonus rewards for a specific lender on a specific roundId
     * @dev run `_calculateRewards` with `_lenderRounds[lender][roundId].bonusAPY` based on the amountLent
     * @param lender, address of the lender to be checked
     * @param roundId, Id of the round to be checked
     * @return returns the amount of bonus rewards in stable (based on stableInstance)
     */
    function bonusRewardOf(address lender, uint roundId)
        external
        view
        returns (uint);

    /**
     * @dev Emitted when `minimumDeposit` is updated
     */
    event MinimumDepositUpdated(
        uint previousMinimumDeposit,
        uint newMinimumDeposit
    );

    /**
     * @dev Emitted when Treasury Address is updated
     */
    event NewTreasuryAddress(
        address oldTreasuryAddress,
        address newTreasuryAddress
    );

    /**
     * @dev Emitted when Tenure is updated
     */
    event TenureUpdated(uint16 oldTenure, uint16 newTenure);

    /**
     * @dev Emitted when `_stableAPY` is updated
     */
    event StableAPYUpdated(uint previousStableAPY, uint newStableAPY);

    /**
     * @dev Emitted when `amount` tokens are deposited into a pool by generating a new Round
     */
    event Deposit(address indexed owner, uint indexed roundId, uint amount);

    /**
     * @dev Emitted when lender withdraw initial `amount` lent on a specific round
     */
    event Withdraw(address indexed owner, uint indexed roundId, uint amount);

    /**
     * @dev Emitted when `lender` claim rewards in Stable coin for a specific round
     */
    event ClaimStable(
        address indexed lender,
        uint indexed roundId,
        uint amount
    );

    /**
     * @dev Emitted when `lender` claim rewards in Trade token for a specific round
     */
    event ClaimTrade(address indexed lender, uint indexed roundId, uint amount);

    /**
     * @dev Emitted when Stable coin are swapped into Trade token
     */
    event Swapped(uint amountStable, uint amountTrade);
}
