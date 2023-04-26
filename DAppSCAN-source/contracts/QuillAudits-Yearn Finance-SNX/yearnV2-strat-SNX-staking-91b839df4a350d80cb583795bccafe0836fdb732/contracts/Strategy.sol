// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseStrategy, VaultAPI} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../interfaces/ISynthetix.sol";
import "../interfaces/IIssuer.sol";
import "../interfaces/IFeePool.sol";
import "../interfaces/IReadProxy.sol";
import "../interfaces/IAddressResolver.sol";
import "../interfaces/IExchangeRates.sol";
import "../interfaces/IRewardEscrowV2.sol";

import "../interfaces/IVault.sol";
import "../interfaces/ISushiRouter.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    uint256 public constant MIN_ISSUE = 50 * 1e18;
    uint256 public ratioThreshold = 1e15;
    uint256 public constant MAX_RATIO = type(uint256).max;
    uint256 public constant MAX_BPS = 10_000;

    address public constant susd =
        address(0x57Ab1ec28D129707052df4dF418D58a2D46d5f51);
    IReadProxy public constant readProxy =
        IReadProxy(address(0x4E3b31eB0E5CB73641EE1E65E7dCEFe520bA3ef2));
    address public constant WETH =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ISushiRouter public constant sushiswap =
        ISushiRouter(address(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F));
    ISushiRouter public constant uniswap =
        ISushiRouter(address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D));
    ISushiRouter public router =
        ISushiRouter(address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D));

    uint256 public targetRatioMultiplier = 12_500;
    IVault public susdVault;

    // to keep track of next entry to vest
    uint256 public entryIDIndex = 0;
    // entryIDs of escrow rewards claimed and to be claimed by the Strategy
    uint256[] public entryIDs;

    bytes32 private constant CONTRACT_SYNTHETIX = "Synthetix";
    bytes32 private constant CONTRACT_EXRATES = "ExchangeRates";
    bytes32 private constant CONTRACT_REWARDESCROW_V2 = "RewardEscrowV2";
    bytes32 private constant CONTRACT_ISSUER = "Issuer";
    bytes32 private constant CONTRACT_FEEPOOL = "FeePool";

    // ********************** EVENTS **********************

    event RepayDebt(uint256 repaidAmount, uint256 debtAfterRepayment);

    // ********************** CONSTRUCTOR **********************

    constructor(address _vault, address _susdVault)
        public
        BaseStrategy(_vault)
    {
        susdVault = IVault(_susdVault);

        // max time between harvest to collect rewards from each epoch
        maxReportDelay = 7 * 24 * 3600;

        // To deposit sUSD in the sUSD vault
        IERC20(susd).safeApprove(address(_susdVault), type(uint256).max);
        // To exchange sUSD for SNX
        IERC20(susd).safeApprove(address(uniswap), type(uint256).max);
        IERC20(susd).safeApprove(address(sushiswap), type(uint256).max);
        // To exchange SNX for sUSD
        IERC20(want).safeApprove(address(uniswap), type(uint256).max);
        IERC20(want).safeApprove(address(sushiswap), type(uint256).max);
    }

    // ********************** SETTERS **********************
    function setRouter(uint256 _isSushi) external onlyAuthorized {
        if (_isSushi == uint256(1)) {
            router = sushiswap;
        } else if (_isSushi == uint256(0)) {
            router = uniswap;
        } else {
            revert("!invalid-arg. Use 1 for sushi. 0 for uni");
        }
    }

    function setTargetRatioMultiplier(uint256 _targetRatioMultiplier) external {
        require(
            msg.sender == governance() ||
                msg.sender == VaultAPI(address(vault)).management()
        );
        targetRatioMultiplier = _targetRatioMultiplier;
    }

    function setRatioThreshold(uint256 _ratioThreshold)
        external
        onlyStrategist
    {
        ratioThreshold = _ratioThreshold;
    }

    // This method is used to migrate the vault where we deposit the sUSD for yield. It should be rarely used
    function migrateSusdVault(IVault newSusdVault, uint256 maxLoss)
        external
        onlyGovernance
    {
        // we tolerate losses to avoid being locked in the vault if things don't work out
        // governance must take this into account before migrating
        susdVault.withdraw(
            susdVault.balanceOf(address(this)),
            address(this),
            maxLoss
        );
        IERC20(susd).safeApprove(address(susdVault), 0);

        susdVault = newSusdVault;
        IERC20(susd).safeApprove(address(newSusdVault), type(uint256).max);
        newSusdVault.deposit();
    }

    // ********************** MANUAL **********************

    function manuallyRepayDebt(uint256 amount) external onlyAuthorized {
        // To be used in case of emergencies, to operate the vault manually
        repayDebt(amount);
    }

    // ********************** YEARN STRATEGY **********************

    function name() external view override returns (string memory) {
        return "StrategySynthetixSusdMinter";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 totalAssets =
            balanceOfWant().add(estimatedProfit()).add(
                sUSDToWant(balanceOfSusdInVault().add(balanceOfSusd()))
            );
        uint256 totalLiabilities = sUSDToWant(balanceOfDebt());
        // NOTE: the ternary operator is required because debt can be higher than assets
        // due to i) increase in debt or ii) losses in invested assets
        return
            totalAssets > totalLiabilities
                ? totalAssets.sub(totalLiabilities)
                : 0;
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        uint256 totalDebt = vault.strategies(address(this)).totalDebt;

        claimProfits();
        vestNextRewardsEntry();

        uint256 totalAssetsAfterProfit = estimatedTotalAssets();

        _profit = totalAssetsAfterProfit > totalDebt
            ? totalAssetsAfterProfit.sub(totalDebt)
            : 0;

        // if the vault is claiming repayment of debt
        if (_debtOutstanding > 0) {
            uint256 _amountFreed = 0;
            (_amountFreed, _loss) = liquidatePosition(_debtOutstanding);
            _debtPayment = Math.min(_debtOutstanding, _amountFreed);

            if (_loss > 0) {
                _profit = 0;
            }
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }

        if (_debtOutstanding >= balanceOfWant()) {
            return;
        }

        // compare current ratio with target ratio
        uint256 _currentRatio = getCurrentRatio();
        // NOTE: target debt ratio is over 20% to maximize APY
        uint256 _targetRatio = getTargetRatio();
        uint256 _issuanceRatio = getIssuanceRatio();
        // burn debt (sUSD) if the ratio is too high
        // collateralisation_ratio = debt / collat

        if (
            _currentRatio > _targetRatio &&
            _currentRatio.sub(_targetRatio) >= ratioThreshold
        ) {
            // NOTE: min threshold to act on differences = 1e16 (ratioThreshold)
            // current debt ratio might be unhealthy
            // we need to repay some debt to get back to the optimal range
            uint256 _debtToRepay =
                balanceOfDebt().sub(getTargetDebt(_collateral()));
            repayDebt(_debtToRepay);
        } else if (
            _issuanceRatio > _currentRatio &&
            _issuanceRatio.sub(_currentRatio) >= ratioThreshold
        ) {
            // NOTE: min threshold to act on differences = 1e16 (ratioThreshold)
            // if there is enough collateral to issue Synth, issue it
            // this should put the c-ratio around 500% (i.e. debt ratio around 20%)
            uint256 _maxSynths = _synthetix().maxIssuableSynths(address(this));
            uint256 _debtBalance = balanceOfDebt();
            // only issue new debt if it is going to be used
            if (
                _maxSynths > _debtBalance &&
                _maxSynths.sub(_debtBalance) >= MIN_ISSUE
            ) {
                _synthetix().issueMaxSynths();
            }
        }

        // If there is susd in the strategy, send it to the susd vault
        // We do MIN_ISSUE instead of 0 since it might be dust
        if (balanceOfSusd() >= MIN_ISSUE) {
            susdVault.deposit();
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // if unlocked collateral balance is not enough, repay debt to unlock
        // enough `want` to repay debt.
        // unlocked collateral includes profit just claimed in `prepareReturn`
        // SWC-Code With No Effects: L253
        uint256 unlockedWant = _unlockedWant();
        if (unlockedWant < _amountNeeded) {
            // NOTE: we use _unlockedWant because `want` balance is the total amount of staked + unstaked want (SNX)
            reduceLockedCollateral(_amountNeeded.sub(unlockedWant));
        }

        // Fetch the unlocked collateral for a second time
        // to update after repaying debt
        // SWC-Code With No Effects: L262
        unlockedWant = _unlockedWant();
        // if not enough want in balance, it means the strategy lost `want`
        if (_amountNeeded > unlockedWant) {
            _liquidatedAmount = unlockedWant;
            _loss = _amountNeeded.sub(unlockedWant);
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function prepareMigration(address _newStrategy) internal override {
        liquidatePosition(vault.strategies(address(this)).totalDebt);
    }

    // ********************** OPERATIONS FUNCTIONS **********************

    function reduceLockedCollateral(uint256 amountToFree) internal {
        // amountToFree cannot be higher than the amount that is unlockable
        amountToFree = Math.min(amountToFree, _unlockableWant());

        if (amountToFree == 0) {
            return;
        }

        uint256 _currentDebt = balanceOfDebt();
        uint256 _newCollateral = _lockedCollateral().sub(amountToFree);
        uint256 _targetDebt = _newCollateral.mul(getIssuanceRatio()).div(1e18);
        // NOTE: _newCollateral will always be < _lockedCollateral() so _targetDebt will always be < _currentDebt
        uint256 _amountToRepay = _currentDebt.sub(_targetDebt);

        repayDebt(_amountToRepay);
    }

    function repayDebt(uint256 amountToRepay) internal {
        // debt can grow over the amount of sUSD minted (see Synthetix docs)
        // if that happens, we might not have enough sUSD to repay debt
        // if we withdraw in this situation, we need to sell `want` to repay debt and would have losses
        // this can only be done if c-Ratio is over 272% (otherwise there is not enough unlocked)
        if (amountToRepay == 0) {
            return;
        }
        uint256 repaidAmount = 0;
        uint256 _debtBalance = balanceOfDebt();
        // max amount to be repaid is the total balanceOfDebt
        amountToRepay = Math.min(_debtBalance, amountToRepay);

        // in case the strategy is going to repay almost all debt, it should repay the total amount of debt
        if (
            _debtBalance > amountToRepay &&
            _debtBalance.sub(amountToRepay) <= MIN_ISSUE
        ) {
            amountToRepay = _debtBalance;
        }

        uint256 currentSusdBalance = balanceOfSusd();
        if (amountToRepay > currentSusdBalance) {
            // there is not enough balance in strategy to repay debt

            // we withdraw from susdvault
            uint256 _withdrawAmount = amountToRepay.sub(currentSusdBalance);
            withdrawFromSUSDVault(_withdrawAmount);
            // we fetch sUSD balance for a second time and check if now there is enough
            currentSusdBalance = balanceOfSusd();
            if (amountToRepay > currentSusdBalance) {
                // there was not enough balance in strategy and sUSDvault to repay debt

                // debt is too high to be repaid using current funds, the strategy should:
                // 1. repay max amount of debt
                // 2. sell unlocked want to buy required sUSD to pay remaining debt
                // 3. repay debt

                if (currentSusdBalance > 0) {
                    // we burn the full sUSD balance to unlock `want` (SNX) in order to sell
                    if (burnSusd(currentSusdBalance)) {
                        // subject to minimumStakePeriod
                        // if successful burnt, update remaining amountToRepay
                        // repaidAmount is previous debt minus current debt
                        repaidAmount = _debtBalance.sub(balanceOfDebt());
                    }
                }
                // buy enough sUSD to repay outstanding debt, selling `want` (SNX)
                // or maximum sUSD with `want` available
                uint256 amountToBuy =
                    Math.min(
                        _getSusdForWant(_unlockedWant()),
                        amountToRepay.sub(repaidAmount)
                    );
                if (amountToBuy > 0) {
                    buySusdWithWant(amountToBuy);
                }
                // amountToRepay should equal balanceOfSusd() (we just bought `amountToRepay` sUSD)
            }
        }

        // repay sUSD debt by burning the synth
        if (amountToRepay > repaidAmount) {
            burnSusd(amountToRepay.sub(repaidAmount)); // this method is subject to minimumStakePeriod (see Synthetix docs)
            repaidAmount = amountToRepay;
        }
        emit RepayDebt(repaidAmount, _debtBalance.sub(repaidAmount));
    }

    // two profit sources: Synthetix protocol and Yearn sUSD Vault
    function claimProfits() internal returns (bool) {
        uint256 feesAvailable;
        uint256 rewardsAvailable;
        (feesAvailable, rewardsAvailable) = _getFeesAvailable();

        if (feesAvailable > 0 || rewardsAvailable > 0) {
            // claim fees from Synthetix
            // claim fees (in sUSD) and rewards (in want (SNX))
            // Synthetix protocol requires issuers to have a c-ratio above 500%
            // to be able to claim fees so we need to burn some sUSD

            // NOTE: we use issuanceRatio because that is what will put us on 500% c-ratio (i.e. 20% debt ratio)
            uint256 _targetDebt =
                getIssuanceRatio().mul(wantToSUSD(_collateral())).div(1e18);
            uint256 _balanceOfDebt = balanceOfDebt();
            bool claim = true;

            if (_balanceOfDebt > _targetDebt) {
                uint256 _requiredPayment = _balanceOfDebt.sub(_targetDebt);
                uint256 _maxCash =
                    balanceOfSusd().add(balanceOfSusdInVault()).mul(50).div(
                        100
                    );
                // only claim rewards if the required payment to burn debt up to c-ratio 500%
                // is less than 50% of available cash (both in strategy and in sUSD vault)
                claim = _requiredPayment <= _maxCash;
            }

            if (claim) {
                // we need to burn sUSD to target
                burnSusdToTarget();

                // if a vesting entry is going to be created,
                // we save its ID to keep track of its vesting
                if (rewardsAvailable > 0) {
                    entryIDs.push(_rewardEscrowV2().nextEntryId());
                }
                // claimFees() will claim both sUSD fees and put SNX rewards in the escrow (in the prev. saved entry)
                _feePool().claimFees();
            }
        }

        // claim profits from Yearn sUSD Vault
        if (balanceOfDebt() < balanceOfSusdInVault()) {
            // balance
            uint256 _valueToWithdraw =
                balanceOfSusdInVault().sub(balanceOfDebt());
            withdrawFromSUSDVault(_valueToWithdraw);
        }

        // sell profits in sUSD for want (SNX) using router
        uint256 _balance = balanceOfSusd();
        if (_balance > 0) {
            buyWantWithSusd(_balance);
        }
    }

    function vestNextRewardsEntry() internal {
        // Synthetix protocol sends SNX staking rewards to a escrow contract that keeps them 52 weeks, until they vest
        // each time we claim the SNX rewards, a VestingEntry is created in the escrow contract for the amount that was owed
        // we need to keep track of those VestingEntries to know when they vest and claim them
        // after they vest and we claim them, we will receive them in our balance (strategy's balance)
        if (entryIDs.length == 0) {
            return;
        }

        // The strategy keeps track of the next VestingEntry expected to vest and only when it has vested, it checks the next one
        // this works because the VestingEntries record has been saved in chronological order and they will vest in chronological order too
        IRewardEscrowV2 re = _rewardEscrowV2();
        uint256 nextEntryID = entryIDs[entryIDIndex];
        uint256 _claimable =
            re.getVestingEntryClaimable(address(this), nextEntryID);
        // check if we need to vest
        if (_claimable == 0) {
            return;
        }

        // vest entryID
        uint256[] memory params = new uint256[](1);
        params[0] = nextEntryID;
        re.vest(params);

        // we update the nextEntryID to point to the next VestingEntry
        entryIDIndex++;
    }

    function tendTrigger(uint256 callCost) public view override returns (bool) {
        uint256 _currentRatio = getCurrentRatio(); // debt / collateral
        uint256 _targetRatio = getTargetRatio(); // max debt ratio. over this number, we consider debt unhealthy
        uint256 _issuanceRatio = getIssuanceRatio(); // preferred debt ratio by Synthetix (See protocol docs)

        if (_currentRatio < _issuanceRatio) {
            // strategy needs to take more debt
            // only return true if the difference is greater than a threshold
            return _issuanceRatio.sub(_currentRatio) >= ratioThreshold;
        } else if (_currentRatio <= _targetRatio) {
            // strategy is in optimal range (a bit undercollateralised)
            return false;
        } else if (_currentRatio > _targetRatio) {
            // the strategy needs to repay debt to exit the danger zone
            // only return true if the difference is greater than a threshold
            return _currentRatio.sub(_targetRatio) >= ratioThreshold;
        }

        return false;
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}

    // ********************** SUPPORT FUNCTIONS  **********************

    function burnSusd(uint256 _amount) internal returns (bool) {
        // returns false if unsuccessful
        if (_issuer().canBurnSynths(address(this))) {
            _synthetix().burnSynths(_amount);
            return true;
        } else {
            return false;
        }
    }

    function burnSusdToTarget() internal returns (uint256) {
        // we use this method to be able to avoid the waiting period
        // (see Synthetix Protocol)
        // it burns enough Synths to get back to 500% c-ratio
        // we need to have enough sUSD to burn to target
        uint256 _debtBalance = balanceOfDebt();
        // NOTE: amount of synths at 500% c-ratio (with current collateral)
        uint256 _maxSynths = _synthetix().maxIssuableSynths(address(this));
        if (_debtBalance <= _maxSynths) {
            // we are over the 500% c-ratio (i.e. below 20% debt ratio), we don't need to burn sUSD
            return 0;
        }
        uint256 _amountToBurn = _debtBalance.sub(_maxSynths);
        uint256 _balance = balanceOfSusd();
        if (_balance < _amountToBurn) {
            // if we do not have enough in balance, we withdraw funds from sUSD vault
            withdrawFromSUSDVault(_amountToBurn.sub(_balance));
        }

        if (_amountToBurn > 0) _synthetix().burnSynthsToTarget();
        return _amountToBurn;
    }

    function withdrawFromSUSDVault(uint256 _amount) internal {
        // Don't leave less than MIN_ISSUE sUSD in the vault
        if (
            _amount > balanceOfSusdInVault() ||
            balanceOfSusdInVault().sub(_amount) <= MIN_ISSUE
        ) {
            susdVault.withdraw();
        } else {
            uint256 _sharesToWithdraw =
                _amount.mul(1e18).div(susdVault.pricePerShare());
            susdVault.withdraw(_sharesToWithdraw);
        }
    }

    function buyWantWithSusd(uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }

        address[] memory path = new address[](3);
        path[0] = address(susd);
        path[1] = address(WETH);
        path[2] = address(want);

        router.swapExactTokensForTokens(_amount, 0, path, address(this), now);
    }

    function buySusdWithWant(uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }

        address[] memory path = new address[](3);
        path[0] = address(want);
        path[1] = address(WETH);
        path[2] = address(susd);

        // we use swapTokensForExactTokens because we need an exact sUSD amount
        router.swapTokensForExactTokens(
            _amount,
            type(uint256).max,
            path,
            address(this),
            now
        );
    }

    // ********************** CALCS **********************

    function estimatedProfit() public view returns (uint256) {
        uint256 availableFees; // in sUSD

        (availableFees, ) = _getFeesAvailable();

        return sUSDToWant(availableFees);
    }

    function getTargetDebt(uint256 _targetCollateral)
        internal
        returns (uint256)
    {
        uint256 _targetRatio = getTargetRatio();
        uint256 _collateralInSUSD = wantToSUSD(_targetCollateral);
        return _targetRatio.mul(_collateralInSUSD).div(1e18);
    }

    function sUSDToWant(uint256 _amount) internal view returns (uint256) {
        if (_amount == 0) {
            return 0;
        }

        return _amount.mul(1e18).div(_exchangeRates().rateForCurrency("SNX"));
    }

    function wantToSUSD(uint256 _amount) internal view returns (uint256) {
        if (_amount == 0) {
            return 0;
        }

        return _amount.mul(_exchangeRates().rateForCurrency("SNX")).div(1e18);
    }

    function _getSusdForWant(uint256 _wantAmount)
        internal
        view
        returns (uint256)
    {
        if (_wantAmount == 0) {
            return 0;
        }
        address[] memory path = new address[](3);
        path[0] = address(want);
        path[1] = address(WETH);
        path[2] = address(susd);

        uint256[] memory amounts = router.getAmountsOut(_wantAmount, path);
        return amounts[amounts.length - 1];
    }

    // ********************** BALANCES & RATIOS **********************
    function _lockedCollateral() internal view returns (uint256) {
        // collateral includes `want` balance (both locked and unlocked) AND escrowed balance
        uint256 _collateral = _synthetix().collateral(address(this));

        return _collateral.sub(_unlockedWant());
    }

    // amount of `want` (SNX) that can be transferred, sold, ...
    function _unlockedWant() internal view returns (uint256) {
        return _synthetix().transferableSynthetix(address(this));
    }

    function _unlockableWant() internal view returns (uint256) {
        // collateral includes escrowed SNX, we may not be able to unlock the full
        // we can only unlock this by repaying debt
        return balanceOfWant().sub(_unlockedWant());
    }

    function _collateral() internal view returns (uint256) {
        return _synthetix().collateral(address(this));
    }

    // returns fees and rewards
    function _getFeesAvailable() internal view returns (uint256, uint256) {
        // fees in sUSD
        // rewards in `want` (SNX)
        return _feePool().feesAvailable(address(this));
    }

    function getCurrentRatio() public view returns (uint256) {
        // ratio = debt / collateral
        // i.e. ratio is 0 if debt is 0
        // NOTE: collateral includes SNX in account + escrowed balance
        return _issuer().collateralisationRatio(address(this));
    }

    function getIssuanceRatio() public view returns (uint256) {
        return _issuer().issuanceRatio();
    }

    function getTargetRatio() public view returns (uint256) {
        return getIssuanceRatio().mul(targetRatioMultiplier).div(MAX_BPS);
    }

    function balanceOfEscrowedWant() public view returns (uint256) {
        return _rewardEscrowV2().balanceOf(address(this));
    }

    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    function balanceOfSusd() public view returns (uint256) {
        return IERC20(susd).balanceOf(address(this));
    }

    function balanceOfDebt() public view returns (uint256) {
        return _synthetix().debtBalanceOf(address(this), "sUSD");
    }

    function balanceOfSusdInVault() public view returns (uint256) {
        return
            susdVault
                .balanceOf(address(this))
                .mul(susdVault.pricePerShare())
                .div(1e18);
    }

    // ********************** ADDRESS RESOLVER SHORTCUTS **********************

    function resolver() public view returns (IAddressResolver) {
        return IAddressResolver(readProxy.target());
    }

    function _synthetix() internal view returns (ISynthetix) {
        return ISynthetix(resolver().getAddress(CONTRACT_SYNTHETIX));
    }

    function _feePool() internal view returns (IFeePool) {
        return IFeePool(resolver().getAddress(CONTRACT_FEEPOOL));
    }

    function _issuer() internal view returns (IIssuer) {
        return IIssuer(resolver().getAddress(CONTRACT_ISSUER));
    }

    function _exchangeRates() internal view returns (IExchangeRates) {
        return IExchangeRates(resolver().getAddress(CONTRACT_EXRATES));
    }

    function _rewardEscrowV2() internal view returns (IRewardEscrowV2) {
        return IRewardEscrowV2(resolver().getAddress(CONTRACT_REWARDESCROW_V2));
    }
}
