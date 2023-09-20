//SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity 0.8.7;

import "../interfaces/IPoolCommitter.sol";
import "../interfaces/ILeveragedPool.sol";
import "../interfaces/IPoolFactory.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./PoolSwapLibrary.sol";

/// @title This contract is responsible for handling commitment logic
contract PoolCommitter is IPoolCommitter, Initializable {
    // #### Globals
    uint128 public constant LONG_INDEX = 0;
    uint128 public constant SHORT_INDEX = 1;

    address public leveragedPool;
    uint128 public updateIntervalId = 1;
    // Index 0 is the LONG token, index 1 is the SHORT token.
    // Fetched from the LeveragedPool when leveragedPool is set
    address[2] public tokens;

    mapping(uint256 => Prices) public priceHistory; // updateIntervalId => tokenPrice
    mapping(address => Balance) public userAggregateBalance;

    // Update interval ID => TotalCommitment
    mapping(uint256 => TotalCommitment) public totalPoolCommitments;
    // Address => Update interval ID => UserCommitment
    mapping(address => mapping(uint256 => UserCommitment)) public userCommitments;
    // The last interval ID for which a given user's balance was updated
    mapping(address => uint256) public lastUpdatedIntervalId;
    // The most recent update interval in which a user committed
    mapping(address => uint256[]) public unAggregatedCommitments;
    // Used to create a dynamic array that is used to copy the new unAggregatedCommitments array into the mapping after updating balance
    uint256[] private storageArrayPlaceHolder;

    address public factory;

    constructor(address _factory) {
        require(_factory != address(0), "Factory address cannot be null");
        factory = _factory;
    }

    function initialize(address _factory) external override initializer {
        require(_factory != address(0), "Factory address cannot be 0 address");
        factory = _factory;
    }

    /**
     * @notice Apply commitment data to storage
     * @param pool The LeveragedPool of this PoolCommitter instance
     * @param commitType The type of commitment being made
     * @param amount The amount of tokens being committed
     * @param fromAggregateBalance If minting, burning, or rebalancing into a delta neutral position,
     *                             will tokens be taken from user's aggregate balance?
     * @param userCommit The appropriate update interval's commitment data for the user
     * @param userCommit The appropriate update interval's commitment data for the entire pool
     */
    function applyCommitment(
        ILeveragedPool pool,
        CommitType commitType,
        uint256 amount,
        bool fromAggregateBalance,
        UserCommitment storage userCommit,
        TotalCommitment storage totalCommit
    ) private {
        Balance memory balance = userAggregateBalance[msg.sender];

        if (commitType == CommitType.LongMint) {
            userCommit.longMintAmount += amount;
            totalCommit.longMintAmount += amount;
            // If we are minting from balance, this would already have thrown in `commit` if we are minting more than entitled too
        } else if (commitType == CommitType.LongBurn) {
            userCommit.longBurnAmount += amount;
            totalCommit.longBurnAmount += amount;
            // long burning: pull in long pool tokens from committer
            if (fromAggregateBalance) {
                // Burning from user's aggregate balance
                userCommit.balanceLongBurnAmount += amount;
                // This require statement is only needed in this branch, as `pool.burnTokens` will revert if burning too many
                require(userCommit.balanceLongBurnAmount <= balance.longTokens, "Insufficient pool tokens");
                // Burn from leveragedPool, because that is the official owner of the tokens before they are claimed
                pool.burnTokens(true, amount, leveragedPool);
            } else {
                // Burning from user's wallet
                pool.burnTokens(true, amount, msg.sender);
            }
        } else if (commitType == CommitType.ShortMint) {
            userCommit.shortMintAmount += amount;
            totalCommit.shortMintAmount += amount;
            // If we are minting from balance, this would already have thrown in `commit` if we are minting more than entitled too
        } else if (commitType == CommitType.ShortBurn) {
            userCommit.shortBurnAmount += amount;
            totalCommit.shortBurnAmount += amount;
            if (fromAggregateBalance) {
                // Burning from user's aggregate balance
                userCommit.balanceShortBurnAmount += amount;
                // This require statement is only needed in this branch, as `pool.burnTokens` will revert if burning too many
                require(userCommit.balanceShortBurnAmount <= balance.shortTokens, "Insufficient pool tokens");
                // Burn from leveragedPool, because that is the official owner of the tokens before they are claimed
                pool.burnTokens(false, amount, leveragedPool);
            } else {
                // Burning from user's wallet
                pool.burnTokens(false, amount, msg.sender);
            }
        } else if (commitType == CommitType.LongBurnShortMint) {
            userCommit.longBurnShortMintAmount += amount;
            totalCommit.longBurnShortMintAmount += amount;
            if (fromAggregateBalance) {
                userCommit.balanceLongBurnMintAmount += amount;
                require(userCommit.balanceLongBurnMintAmount <= balance.longTokens, "Insufficient pool tokens");
                pool.burnTokens(true, amount, leveragedPool);
            } else {
                pool.burnTokens(true, amount, msg.sender);
            }
        } else if (commitType == CommitType.ShortBurnLongMint) {
            userCommit.shortBurnLongMintAmount += amount;
            totalCommit.shortBurnLongMintAmount += amount;
            if (fromAggregateBalance) {
                userCommit.balanceShortBurnMintAmount += amount;
                require(userCommit.balanceShortBurnMintAmount <= balance.shortTokens, "Insufficient pool tokens");
                pool.burnTokens(false, amount, leveragedPool);
            } else {
                pool.burnTokens(false, amount, msg.sender);
            }
        }
    }

    /**
     * @notice Commit to minting/burning long/short tokens after the next price change
     * @param commitType Type of commit you're doing (Long vs Short, Mint vs Burn)
     * @param amount Amount of quote tokens you want to commit to minting; OR amount of pool
     *               tokens you want to burn
     * @param fromAggregateBalance If minting, burning, or rebalancing into a delta neutral position,
     *                             will tokens be taken from user's aggregate balance?
     */
    // SWC-114-Transaction Order Dependence: L139-L181
    function commit(
        CommitType commitType,
        uint256 amount,
        bool fromAggregateBalance
    ) external override updateBalance {
        require(amount > 0, "Amount must not be zero");
        ILeveragedPool pool = ILeveragedPool(leveragedPool);
        uint256 updateInterval = pool.updateInterval();
        uint256 lastPriceTimestamp = pool.lastPriceTimestamp();
        uint256 frontRunningInterval = pool.frontRunningInterval();

        uint256 appropriateUpdateIntervalId = PoolSwapLibrary.appropriateUpdateIntervalId(
            block.timestamp,
            lastPriceTimestamp,
            frontRunningInterval,
            updateInterval,
            updateIntervalId
        );
        TotalCommitment storage totalCommit = totalPoolCommitments[appropriateUpdateIntervalId];
        UserCommitment storage userCommit = userCommitments[msg.sender][appropriateUpdateIntervalId];

        userCommit.updateIntervalId = appropriateUpdateIntervalId;

        uint256 length = unAggregatedCommitments[msg.sender].length;
        if (length == 0 || unAggregatedCommitments[msg.sender][length - 1] < appropriateUpdateIntervalId) {
            unAggregatedCommitments[msg.sender].push(appropriateUpdateIntervalId);
        }

        if (commitType == CommitType.LongMint || commitType == CommitType.ShortMint) {
            // minting: pull in the quote token from the committer
            // Do not need to transfer if minting using aggregate balance tokens, since the leveraged pool already owns these tokens.
            if (!fromAggregateBalance) {
                pool.quoteTokenTransferFrom(msg.sender, leveragedPool, amount);
            } else {
                // Want to take away from their balance's settlement tokens
                userAggregateBalance[msg.sender].settlementTokens -= amount;
            }
        }

        applyCommitment(pool, commitType, amount, fromAggregateBalance, userCommit, totalCommit);

        emit CreateCommit(msg.sender, amount, commitType);
    }

    /**
     * @notice Claim user's balance. This can be done either by the user themself or by somebody else on their behalf.
     */
    // SWC-114-Transaction Order Dependence: L187-L201
    function claim(address user) external override updateBalance {
        Balance memory balance = userAggregateBalance[user];
        ILeveragedPool pool = ILeveragedPool(leveragedPool);
        if (balance.settlementTokens > 0) {
            pool.quoteTokenTransfer(user, balance.settlementTokens);
        }
        if (balance.longTokens > 0) {
            pool.poolTokenTransfer(true, user, balance.longTokens);
        }
        if (balance.shortTokens > 0) {
            pool.poolTokenTransfer(false, user, balance.shortTokens);
        }
        delete userAggregateBalance[user];
        emit Claim(user);
    }

    function executeGivenCommitments(TotalCommitment memory _commits) internal {
        ILeveragedPool pool = ILeveragedPool(leveragedPool);

        BalancesAndSupplies memory balancesAndSupplies = BalancesAndSupplies({
            shortBalance: pool.shortBalance(),
            longBalance: pool.longBalance(),
            longTotalSupplyBefore: IERC20(tokens[0]).totalSupply(),
            shortTotalSupplyBefore: IERC20(tokens[1]).totalSupply()
        });

        uint256 totalLongBurn = _commits.longBurnAmount + _commits.longBurnShortMintAmount;
        uint256 totalShortBurn = _commits.shortBurnAmount + _commits.shortBurnLongMintAmount;
        // Update price before values change
        priceHistory[updateIntervalId] = Prices({
            longPrice: PoolSwapLibrary.getPrice(
                balancesAndSupplies.longBalance,
                balancesAndSupplies.longTotalSupplyBefore + totalLongBurn
            ),
            shortPrice: PoolSwapLibrary.getPrice(
                balancesAndSupplies.shortBalance,
                balancesAndSupplies.shortTotalSupplyBefore + totalShortBurn
            )
        });

        // Amount of collateral tokens that are generated from the long burn into instant mints
        uint256 longBurnInstantMintAmount = PoolSwapLibrary.getWithdrawAmountOnBurn(
            balancesAndSupplies.longTotalSupplyBefore,
            _commits.longBurnShortMintAmount,
            balancesAndSupplies.longBalance,
            totalLongBurn
        );
        // Amount of collateral tokens that are generated from the short burn into instant mints
        uint256 shortBurnInstantMintAmount = PoolSwapLibrary.getWithdrawAmountOnBurn(
            balancesAndSupplies.shortTotalSupplyBefore,
            _commits.shortBurnLongMintAmount,
            balancesAndSupplies.shortBalance,
            totalShortBurn
        );

        // Long Mints
        uint256 longMintAmount = PoolSwapLibrary.getMintAmount(
            balancesAndSupplies.longTotalSupplyBefore, // long token total supply,
            _commits.longMintAmount + shortBurnInstantMintAmount, // Add the collateral tokens that will be generated from burning shorts for instant long mint
            balancesAndSupplies.longBalance, // total quote tokens in the long pull
            totalLongBurn // total pool tokens commited to be burned
        );

        if (longMintAmount > 0) {
            pool.mintTokens(true, longMintAmount, leveragedPool);
        }

        // Long Burns
        uint256 longBurnAmount = PoolSwapLibrary.getWithdrawAmountOnBurn(
            balancesAndSupplies.longTotalSupplyBefore,
            totalLongBurn,
            balancesAndSupplies.longBalance,
            totalLongBurn
        );

        // Short Mints
        uint256 shortMintAmount = PoolSwapLibrary.getMintAmount(
            balancesAndSupplies.shortTotalSupplyBefore, // short token total supply
            _commits.shortMintAmount + longBurnInstantMintAmount, // Add the collateral tokens that will be generated from burning longs for instant short mint
            balancesAndSupplies.shortBalance,
            totalShortBurn
        );

        if (shortMintAmount > 0) {
            pool.mintTokens(false, shortMintAmount, leveragedPool);
        }

        // Short Burns
        uint256 shortBurnAmount = PoolSwapLibrary.getWithdrawAmountOnBurn(
            balancesAndSupplies.shortTotalSupplyBefore,
            totalShortBurn,
            balancesAndSupplies.shortBalance,
            totalShortBurn
        );

        uint256 newLongBalance = balancesAndSupplies.longBalance +
            _commits.longMintAmount -
            longBurnAmount +
            shortBurnInstantMintAmount;
        uint256 newShortBalance = balancesAndSupplies.shortBalance +
            _commits.shortMintAmount -
            shortBurnAmount +
            longBurnInstantMintAmount;

        // Update the collateral on each side
        pool.setNewPoolBalances(newLongBalance, newShortBalance);
    }

    function executeCommitments() external override onlyPool {
        ILeveragedPool pool = ILeveragedPool(leveragedPool);
        executeGivenCommitments(totalPoolCommitments[updateIntervalId]);
        delete totalPoolCommitments[updateIntervalId];
        updateIntervalId += 1;

        uint32 counter = 2;
        uint256 lastPriceTimestamp = pool.lastPriceTimestamp();
        uint256 updateInterval = pool.updateInterval();
        // SWC-128-DoS With Block Gas Limit: L305-L315
        while (true) {
            if (block.timestamp >= lastPriceTimestamp + updateInterval * counter) {
                // Another update interval has passed, so we have to do the nextIntervalCommit as well
                executeGivenCommitments(totalPoolCommitments[updateIntervalId]);
                delete totalPoolCommitments[updateIntervalId];
                updateIntervalId += 1;
            } else {
                break;
            }
            counter += 1;
        }
    }

    function updateBalanceSingleCommitment(UserCommitment memory _commit)
        internal
        view
        returns (
            uint256 _newLongTokens,
            uint256 _newShortTokens,
            uint256 _newSettlementTokens
        )
    {
        PoolSwapLibrary.UpdateData memory updateData = PoolSwapLibrary.UpdateData({
            longPrice: priceHistory[_commit.updateIntervalId].longPrice,
            shortPrice: priceHistory[_commit.updateIntervalId].shortPrice,
            currentUpdateIntervalId: updateIntervalId,
            updateIntervalId: _commit.updateIntervalId,
            longMintAmount: _commit.longMintAmount,
            longBurnAmount: _commit.longBurnAmount,
            shortMintAmount: _commit.shortMintAmount,
            shortBurnAmount: _commit.shortBurnAmount,
            longBurnShortMintAmount: _commit.longBurnShortMintAmount,
            shortBurnLongMintAmount: _commit.shortBurnLongMintAmount
        });

        (_newLongTokens, _newShortTokens, _newSettlementTokens) = PoolSwapLibrary.getUpdatedAggregateBalance(
            updateData
        );
    }

    /**
     * @notice Add the result of a user's most recent commit to their aggregateBalance
     */
    function updateAggregateBalance(address user) public override {
        Balance storage balance = userAggregateBalance[user];

        BalanceUpdate memory update = BalanceUpdate({
            _updateIntervalId: updateIntervalId,
            _newLongTokensSum: 0,
            _newShortTokensSum: 0,
            _newSettlementTokensSum: 0,
            _balanceLongBurnAmount: 0,
            _balanceShortBurnAmount: 0
        });

        // Iterate from the most recent up until the current update interval

        uint256[] memory currentIntervalIds = unAggregatedCommitments[user];
        uint256 unAggregatedLength = currentIntervalIds.length;
        for (uint256 i = 0; i < unAggregatedLength; i++) {
            uint256 id = currentIntervalIds[i];
            if (currentIntervalIds[i] == 0) {
                continue;
            }
            UserCommitment memory commitment = userCommitments[user][id];

            /* If the update interval of commitment has not yet passed, we still
            want to deduct burns from the balance from a user's balance.
            Therefore, this should happen outside of the if block below.*/
            update._balanceLongBurnAmount += commitment.balanceLongBurnAmount + commitment.balanceLongBurnMintAmount;
            update._balanceShortBurnAmount += commitment.balanceShortBurnAmount + commitment.balanceShortBurnMintAmount;
            if (commitment.updateIntervalId < updateIntervalId) {
                (
                    uint256 _newLongTokens,
                    uint256 _newShortTokens,
                    uint256 _newSettlementTokens
                ) = updateBalanceSingleCommitment(commitment);
                update._newLongTokensSum += _newLongTokens;
                update._newShortTokensSum += _newShortTokens;
                update._newSettlementTokensSum += _newSettlementTokens;
                // SWC-135-Code With No Effects: L386
                delete userCommitments[user][i];
                delete unAggregatedCommitments[user][i];
            } else {
                // Clear them now that they have been accounted for in the balance
                userCommitments[user][id].balanceLongBurnAmount = 0;
                userCommitments[user][id].balanceShortBurnAmount = 0;
                userCommitments[user][id].balanceLongBurnMintAmount = 0;
                userCommitments[user][id].balanceShortBurnMintAmount = 0;
                // This commitment wasn't ready to be completely added to the balance, so copy it over into the new ID array
                storageArrayPlaceHolder.push(currentIntervalIds[i]);
            }
        }

        delete unAggregatedCommitments[user];
        unAggregatedCommitments[user] = storageArrayPlaceHolder;

        delete storageArrayPlaceHolder;

        // Add new tokens minted, and remove the ones that were burnt from this balance
        balance.longTokens += update._newLongTokensSum;
        balance.longTokens -= update._balanceLongBurnAmount;
        balance.shortTokens += update._newShortTokensSum;
        balance.shortTokens -= update._balanceShortBurnAmount;
        balance.settlementTokens += update._newSettlementTokensSum;

        emit AggregateBalanceUpdated(user);
    }

    /**
     * @notice A copy of updateAggregateBalance that returns the aggregate balance without updating it
     */
    function getAggregateBalance(address user) public view override returns (Balance memory) {
        Balance memory _balance = userAggregateBalance[user];

        BalanceUpdate memory update = BalanceUpdate({
            _updateIntervalId: updateIntervalId,
            _newLongTokensSum: 0,
            _newShortTokensSum: 0,
            _newSettlementTokensSum: 0,
            _balanceLongBurnAmount: 0,
            _balanceShortBurnAmount: 0
        });

        // Iterate from the most recent up until the current update interval

        uint256[] memory currentIntervalIds = unAggregatedCommitments[user];
        uint256 unAggregatedLength = currentIntervalIds.length;
        for (uint256 i = 0; i < unAggregatedLength; i++) {
            uint256 id = currentIntervalIds[i];
            if (currentIntervalIds[i] == 0) {
                continue;
            }
            UserCommitment memory commitment = userCommitments[user][id];

            /* If the update interval of commitment has not yet passed, we still
            want to deduct burns from the balance from a user's balance.
            Therefore, this should happen outside of the if block below.*/
            update._balanceLongBurnAmount += commitment.balanceLongBurnAmount + commitment.balanceLongBurnMintAmount;
            update._balanceShortBurnAmount += commitment.balanceShortBurnAmount + commitment.balanceShortBurnMintAmount;
            if (commitment.updateIntervalId < updateIntervalId) {
                (
                    uint256 _newLongTokens,
                    uint256 _newShortTokens,
                    uint256 _newSettlementTokens
                ) = updateBalanceSingleCommitment(commitment);
                update._newLongTokensSum += _newLongTokens;
                update._newShortTokensSum += _newShortTokens;
                update._newSettlementTokensSum += _newSettlementTokens;
            }
        }

        // Add new tokens minted, and remove the ones that were burnt from this balance
        _balance.longTokens += update._newLongTokensSum;
        _balance.longTokens -= update._balanceLongBurnAmount;
        _balance.shortTokens += update._newShortTokensSum;
        _balance.shortTokens -= update._balanceShortBurnAmount;
        _balance.settlementTokens += update._newSettlementTokensSum;

        return _balance;
    }

    function setQuoteAndPool(address _quoteToken, address _leveragedPool) external override onlyFactory {
        require(_quoteToken != address(0), "Quote token address cannot be 0 address");
        require(_leveragedPool != address(0), "Leveraged pool address cannot be 0 address");

        leveragedPool = _leveragedPool;
        IERC20 _token = IERC20(_quoteToken);
        bool approvalSuccess = _token.approve(leveragedPool, _token.totalSupply());
        require(approvalSuccess, "ERC20 approval failed");
        tokens = ILeveragedPool(leveragedPool).poolTokens();
    }

    modifier updateBalance() {
        updateAggregateBalance(msg.sender);
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "Committer: not factory");
        _;
    }

    modifier onlyPool() {
        require(msg.sender == leveragedPool, "msg.sender not leveragedPool");
        _;
    }
}
