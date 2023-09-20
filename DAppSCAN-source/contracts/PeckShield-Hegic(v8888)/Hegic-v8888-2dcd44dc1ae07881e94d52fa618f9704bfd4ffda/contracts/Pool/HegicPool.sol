pragma solidity 0.8.6;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Hegic
 * Copyright (C) 2021 Hegic Protocol
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

import "../Interfaces/Interfaces.sol";
import "../Interfaces/IOptionsManager.sol";
import "../Interfaces/Interfaces.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @author 0mllwntrmt3
 * @title Hegic Protocol V8888 Main Pool Contract
 * @notice One of the main contracts that manages the pools and the options parameters,
 * accumulates the funds from the liquidity providers and makes the withdrawals for them,
 * sells the options contracts to the options buyers and collateralizes them,
 * exercises the ITM (in-the-money) options with the unrealized P&L and settles them,
 * unlocks the expired options and distributes the premiums among the liquidity providers.
 **/
abstract contract HegicPool is IHegicPool, ERC721, AccessControl {
    using SafeERC20 for IERC20;

    uint256 public constant INITIAL_RATE = 1e20;
    IOptionsManager public immutable optionsManager;
    AggregatorV3Interface public immutable priceProvider;
    IPriceCalculator public override pricer;
    uint256 public lockupPeriodForHedgedTranches = 60 days;
    uint256 public lockupPeriodForUnhedgedTranches = 30 days;
    uint256 public hedgeFeeRate = 80;
    uint256 public maxUtilizationRate = 80;
    uint256 public collateralizationRatio = 50;
    uint256 public override lockedAmount;
    uint256 public maxDepositAmount = type(uint256).max;
    uint256 public maxHedgedDepositAmount = type(uint256).max;

    uint256 public unhedgedShare = 0;
    uint256 public hedgedShare = 0;
    uint256 public override unhedgedBalance = 0;
    uint256 public override hedgedBalance = 0;
    IHegicStaking public settlementFeeRecipient;
    address public hedgePool;

    Tranche[] public override tranches;
    mapping(uint256 => Option) public override options;
    IERC20 public override token;

    constructor(
        IERC20 _token,
        string memory name,
        string memory symbol,
        IOptionsManager manager,
        IPriceCalculator _pricer,
        IHegicStaking _settlementFeeRecipient,
        AggregatorV3Interface _priceProvider
    ) ERC721(name, symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        priceProvider = _priceProvider;
        settlementFeeRecipient = _settlementFeeRecipient;
        pricer = _pricer;
        token = _token;
        hedgePool = _msgSender();
        optionsManager = manager;
        approve();
    }

    /**
     * @notice Used for setting the liquidity lock-up periods during which
     * the liquidity providers who deposited the funds into the pools contracts
     * won't be able to withdraw them. Note that different lock-ups could
     * be set for the hedged and unhedged — classic — liquidity tranches.
     * @param hedgedValue Hedged liquidity tranches lock-up in seconds
     * @param unhedgedValue Unhedged (classic) liquidity tranches lock-up in seconds
     **/
    function setLockupPeriod(uint256 hedgedValue, uint256 unhedgedValue)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(
            hedgedValue <= 60 days,
            "The lockup period for hedged tranches is too long"
        );
        require(
            unhedgedValue <= 30 days,
            "The lockup period for unhedged tranches is too long"
        );
        lockupPeriodForHedgedTranches = hedgedValue;
        lockupPeriodForUnhedgedTranches = unhedgedValue;
    }

    /**
     * @notice Used for setting the total maximum amount
     * that could be deposited into the pools contracts.
     * Note that different total maximum amounts could be set
     * for the hedged and unhedged — classic — liquidity tranches.
     * @param total Maximum amount of assets in the pool
     * in hedged and unhedged (classic) liquidity tranches combined
     * @param hedged Maximum amount of assets in the pool
     * in hedged liquidity tranches only
     **/
    function setMaxDepositAmount(uint256 total, uint256 hedged)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(
            total >= hedged,
            "Pool Error: The total amount shouldn't be lower than the hedged amount"
        );
        maxDepositAmount = total;
        maxHedgedDepositAmount = hedged;
    }

    /**
     * @notice Used for setting the maximum share of the pool
     * size that could be utilized as a collateral in the options.
     *
     * Example: if `MaxUtilizationRate` = 50, then only 50%
     * of liquidity on the pools contracts would be used for
     * collateralizing options while 50% will be sitting idle
     * available for withdrawals by the liquidity providers.
     * @param value The utilization ratio in a range of 50% — 100%
     **/
    function setMaxUtilizationRate(uint256 value)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(
            50 <= value && value <= 100,
            "Pool error: Wrong utilization rate limitation value"
        );
        maxUtilizationRate = value;
    }

    /**
     * @notice Used for setting the collateralization ratio for the option
     * collateral size that will be locked at the moment of buying them.
     *
     * Example: if `CollateralizationRatio` = 50, then 50% of an option's
     * notional size will be locked in the pools at the moment of buying it:
     * say, 1 ETH call option will be collateralized with 0.5 ETH (50%).
     * Note that if an option holder's net P&L USD value (as options
     * are cash-settled) will exceed the amount of the collateral locked
     * in the option, she will receive the required amount at the moment
     * of exercising the option using the pool's unutilized (unlocked) funds.
     * @param value The collateralization ratio in a range of 30% — 100%
     **/
    function setCollateralizationRatio(uint256 value)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(
            30 <= value && value <= 100,
            "Pool Error: Wrong collateralization ratio value"
        );
        collateralizationRatio = value;
    }

    /**
     * @dev See EIP-165: ERC-165 Standard Interface Detection
     * https://eips.ethereum.org/EIPS/eip-165.
     **/
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, AccessControl, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IHegicPool).interfaceId ||
            AccessControl.supportsInterface(interfaceId) ||
            ERC721.supportsInterface(interfaceId);
    }

    /**
     * @notice Used for approving the staking contracts
     * to receive the `settlementFee` in ERC20 tokens
     * that will be accumulated and distributed in
     * staking rewards among the staking participants.
     **/
    function approve() public {
        token.approve(address(settlementFeeRecipient), type(uint256).max);
    }

    /**
     * @notice Used for changing the hedging pool address
     * that will be accumulating the hedging premiums paid
     * as a share of the total premium redirected to this address.
     * @param value The address for receiving hedging premiums
     **/
    function setHedgePool(address value)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(value != address(0));
        hedgePool = value;
    }

    /**
     * @notice Used for selling the options contracts
     * with the parameters chosen by the option buyer
     * such as the period of holding, option size (amount),
     * strike price and the premium to be paid for the option.
     * @param holder The option buyer address
     * @param period The option period
     * @param amount The option size
     * @param strike The option strike
     * @return id ID of ERC721 token linked to the option
     **/
    function sellOption(
        address holder,
        uint256 period,
        uint256 amount,
        uint256 strike
    ) external override returns (uint256 id) {
        if (strike == 0) strike = _currentPrice();
        uint256 balance = totalBalance();
        uint256 amountToBeLocked = _calculateLockedAmount(amount);

        require(period >= 1 days, "Pool Error: The period is too short");
        require(period <= 90 days, "Pool Error: The period is too long");
        require(
            (lockedAmount + amountToBeLocked) * 100 <=
                balance * maxUtilizationRate,
            "Pool Error: The amount is too large"
        );

        (uint256 settlementFee, uint256 premium) =
            _calculateTotalPremium(period, amount, strike);
        uint256 hedgedPremiumTotal = (premium * hedgedBalance) / balance;
        uint256 hedgeFee = (hedgedPremiumTotal * hedgeFeeRate) / 100;
        uint256 hedgePremium = hedgedPremiumTotal - hedgeFee;
        uint256 unhedgePremium = premium - hedgedPremiumTotal;

        lockedAmount += amountToBeLocked;
        id = optionsManager.createOptionFor(holder);
        options[id] = Option(
            OptionState.Active,
            strike,
            amount,
            amountToBeLocked,
            block.timestamp,
            block.timestamp + period,
            hedgePremium,
            unhedgePremium
        );

        token.safeTransferFrom(
            _msgSender(),
            address(this),
            premium + settlementFee
        );

        settlementFeeRecipient.sendProfits(settlementFee);
        if (hedgeFee > 0) token.safeTransfer(hedgePool, hedgeFee);
        emit Acquired(id, settlementFee, premium);
    }

    /**
     * @notice Used for setting the price calculator
     * contract that will be used for pricing the options.
     * @param pc A new price calculator contract address
     **/
    function setPriceCalculator(IPriceCalculator pc)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        pricer = pc;
    }

    /**
     * @notice Used for exercising the ITM (in-the-money)
     * options contracts in case of having the unrealized profits
     * accrued during the period of holding the option contract.
     * @param id ID of ERC721 token linked to the option
     **/
    function exercise(uint256 id) external override {
        Option storage option = options[id];
        uint256 profit = _profitOf(option);
        require(
            optionsManager.isApprovedOrOwner(_msgSender(), id),
            "Pool Error: msg.sender can't exercise this option"
        );
        require(
            option.expired > block.timestamp,
            "Pool Error: The option has already expired"
        );
        require(
            profit > 0,
            "Pool Error: There are no unrealized profits for this option"
        );
        _unlock(option);
        option.state = OptionState.Exercised;
        _send(optionsManager.ownerOf(id), profit);
        emit Exercised(id, profit);
    }

    function _send(address to, uint256 transferAmount) private {
        require(to != address(0));
        uint256 hedgeLoss = (transferAmount * hedgedBalance) / totalBalance();
        uint256 unhedgeLoss = transferAmount - hedgeLoss;
        hedgedBalance -= hedgeLoss;
        unhedgedBalance -= unhedgeLoss;
        token.safeTransfer(to, transferAmount);
    }

    /**
     * @notice Used for unlocking the expired OTM (out-of-the-money)
     * options contracts in case if there was no unrealized P&L
     * accrued during the period of holding a particular option.
     * Note that the `unlock` function releases the liquidity that
     * was locked in the option when it was active and the premiums
     * that are distributed pro rata among the liquidity providers.
     * @param id ID of ERC721 token linked to the option
     **/
    function unlock(uint256 id) external override {
        Option storage option = options[id];
        require(
            option.expired < block.timestamp,
            "Pool Error: The option has not expired yet"
        );
        _unlock(option);
        option.state = OptionState.Expired;
        emit Expired(id);
    }

    function _unlock(Option storage option) internal {
        require(
            option.state == OptionState.Active,
            "Pool Error: The option with such an ID has already been exercised or expired"
        );
        lockedAmount -= option.lockedAmount;
        hedgedBalance += option.hedgePremium;
        unhedgedBalance += option.unhedgePremium;
    }

    function _calculateLockedAmount(uint256 amount)
        internal
        virtual
        returns (uint256)
    {
        return (amount * collateralizationRatio) / 100;
    }

    /**
     * @notice Used for depositing the funds into the pool
     * and minting the liquidity tranche ERC721 token
     * which represents the liquidity provider's share
     * in the pool and her unrealized P&L for this tranche.
     * @param account The liquidity provider's address
     * @param amount The size of the liquidity tranche
     * @param hedged The type of the liquidity tranche
     * @param minShare The minimum share in the pool for the user
     **/
    //  SWC-107-Reentrancy: L373 - L409
    function provideFrom(
        address account,
        uint256 amount,
        bool hedged,
        uint256 minShare
    ) external override returns (uint256 share) {
        uint256 totalShare = hedged ? hedgedShare : unhedgedShare;
        uint256 balance = hedged ? hedgedBalance : unhedgedBalance;
        share = totalShare > 0 && balance > 0
            ? (amount * totalShare) / balance
            : amount * INITIAL_RATE;
        uint256 limit =
            hedged
                ? maxHedgedDepositAmount - hedgedBalance
                : maxDepositAmount - hedgedBalance - unhedgedBalance;
        require(share >= minShare, "Pool Error: The mint limit is too large");
        require(share > 0, "Pool Error: The amount is too small");
        require(
            amount <= limit,
            "Pool Error: Depositing into the pool is not available"
        );

        if (hedged) {
            hedgedShare += share;
            hedgedBalance += amount;
        } else {
            unhedgedShare += share;
            unhedgedBalance += amount;
        }

        uint256 trancheID = tranches.length;
        tranches.push(
            Tranche(TrancheState.Open, share, amount, block.timestamp, hedged)
        );
        _safeMint(account, trancheID);
        token.safeTransferFrom(_msgSender(), address(this), amount);
    }

    /**
     * @notice Used for withdrawing the funds from the pool
     * plus the net positive P&L earned or
     * minus the net negative P&L lost on
     * providing liquidity and selling options.
     * @param trancheID The liquidity tranche ID
     * @return amount The amount received after the withdrawal
     **/
    function withdraw(uint256 trancheID)
        external
        override
        returns (uint256 amount)
    {
        address owner = ownerOf(trancheID);
        Tranche memory t = tranches[trancheID];
        amount = _withdraw(owner, trancheID);
        if (t.hedged && amount < t.amount) {
            token.safeTransferFrom(hedgePool, owner, t.amount - amount);
            amount = t.amount;
        }
        emit Withdrawn(owner, trancheID, amount);
    }

    /**
     * @notice Used for withdrawing the funds from the pool
     * by the hedged liquidity tranches providers
     * in case of an urgent need to withdraw the liquidity
     * without receiving the loss compensation from
     * the hedging pool: the net difference between
     * the amount deposited and the withdrawal amount.
     * @param trancheID ID of liquidity tranche
     * @return amount The amount received after the withdrawal
     **/
    function withdrawWithoutHedge(uint256 trancheID)
        external
        override
        returns (uint256 amount)
    {
        address owner = ownerOf(trancheID);
        amount = _withdraw(owner, trancheID);
        emit Withdrawn(owner, trancheID, amount);
    }

    function _withdraw(address owner, uint256 trancheID)
        internal
        returns (uint256 amount)
    {
        Tranche storage t = tranches[trancheID];
        uint256 lockupPeriod =
            t.hedged
                ? lockupPeriodForHedgedTranches
                : lockupPeriodForUnhedgedTranches;
        require(t.state == TrancheState.Open);
        require(_isApprovedOrOwner(_msgSender(), trancheID));
        require(
            block.timestamp > t.creationTimestamp + lockupPeriod,
            "Pool Error: The withdrawal is locked up"
        );

        t.state = TrancheState.Closed;
        if (t.hedged) {
            amount = (t.share * hedgedBalance) / hedgedShare;
            hedgedShare -= t.share;
            hedgedBalance -= amount;
        } else {
            amount = (t.share * unhedgedBalance) / unhedgedShare;
            unhedgedShare -= t.share;
            unhedgedBalance -= amount;
        }

        token.safeTransfer(owner, amount);
    }

    /**
     * @return balance Returns the amount of liquidity available for withdrawing
     **/
    function availableBalance() public view returns (uint256 balance) {
        return totalBalance() - lockedAmount;
    }

    /**
     * @return balance Returns the total balance of liquidity provided to the pool
     **/
    function totalBalance() public view override returns (uint256 balance) {
        return hedgedBalance + unhedgedBalance;
    }

    function _beforeTokenTransfer(
        address,
        address,
        uint256 id
    ) internal view override {
        require(
            tranches[id].state == TrancheState.Open,
            "Pool Error: The closed tranches can not be transferred"
        );
    }

    /**
     * @notice Returns the amount of unrealized P&L of the option
     * that could be received by the option holder in case
     * if she exercises it as an ITM (in-the-money) option.
     * @param id ID of ERC721 token linked to the option
     **/
    function profitOf(uint256 id) external view returns (uint256) {
        return _profitOf(options[id]);
    }

    function _profitOf(Option memory option)
        internal
        view
        virtual
        returns (uint256 amount);

    /**
     * @notice Used for calculating the `TotalPremium`
     * for the particular option with regards to
     * the parameters chosen by the option buyer
     * such as the period of holding, size (amount)
     * and strike price.
     * @param period The period of holding the option
     * @param period The size of the option
     **/
    function calculateTotalPremium(
        uint256 period,
        uint256 amount,
        uint256 strike
    ) external view override returns (uint256 settlementFee, uint256 premium) {
        return _calculateTotalPremium(period, amount, strike);
    }

    function _calculateTotalPremium(
        uint256 period,
        uint256 amount,
        uint256 strike
    ) internal view virtual returns (uint256 settlementFee, uint256 premium) {
        (settlementFee, premium) = pricer.calculateTotalPremium(
            period,
            amount,
            strike
        );
        require(
            settlementFee + premium > amount / 1000,
            "HegicPool: The option's price is too low"
        );
    }

    /**
     * @notice Used for changing the `settlementFeeRecipient`
     * contract address for distributing the settlement fees
     * (staking rewards) among the staking participants.
     * @param recipient New staking contract address
     **/
    function setSettlementFeeRecipient(IHegicStaking recipient)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(address(recipient) != address(0));
        settlementFeeRecipient = recipient;
    }

    function _currentPrice() internal view returns (uint256 price) {
        (, int256 latestPrice, , , ) = priceProvider.latestRoundData();
        price = uint256(latestPrice);
    }
}
