// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";
import "@openzeppelin/contracts/math/Math.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./libraries/MakerDaiDelegateLib.sol";

import "../interfaces/chainlink/AggregatorInterface.sol";
import "../interfaces/swap/ISwap.sol";
import "../interfaces/yearn/IOSMedianizer.sol";
import "../interfaces/yearn/IVault.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // Units used in Maker contracts
    uint256 internal constant WAD = 10**18;
    uint256 internal constant RAY = 10**27;

    // DAI token
    IERC20 internal constant investmentToken =
        IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    // 100%
    uint256 internal constant MAX_BPS = WAD;

    // Maximum loss on withdrawal from yVault
    uint256 internal constant MAX_LOSS_BPS = 10000;

    // Wrapped Ether - Used for swaps routing
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // SushiSwap router
    ISwap internal constant sushiswapRouter =
        ISwap(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    // Uniswap router
    ISwap internal constant uniswapRouter =
        ISwap(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // Token Adapter Module for collateral
    address public gemJoinAdapter;

    // Maker Oracle Security Module
    IOSMedianizer public wantToUSDOSMProxy;

    // Use Chainlink oracle to obtain latest want/ETH price
    AggregatorInterface public chainlinkWantToETHPriceFeed;

    // Use Chainlink oracle to obtain latest want/USD price
    AggregatorInterface public chainlinkWantToUSDPriceFeed;

    // DAI yVault
    IVault public yVault;

    // Router used for swaps
    ISwap public router;

    // Collateral type
    bytes32 public ilk;

    // Our vault identifier
    uint256 public cdpId;

    // Our desired collaterization ratio
    uint256 public collateralizationRatio;

    // Allow the collateralization ratio to drift a bit in order to avoid cycles
    uint256 public rebalanceTolerance;

    // Maximum acceptable loss on withdrawal. Default to 0.01%.
    uint256 public maxLoss;

    // If set to true the strategy will never try to repay debt by selling want
    bool public leaveDebtBehind;

    // Name of the strategy
    string internal strategyName;

    // ----------------- INIT FUNCTIONS TO SUPPORT CLONING -----------------

    constructor(
        address _vault,
        address _yVault,
        string memory _strategyName,
        bytes32 _ilk,
        address _gemJoin,
        address _wantToUSDOSMProxy,
        address _chainlinkWantToUSDPriceFeed,
        address _chainlinkWantToETHPriceFeed
    ) public BaseStrategy(_vault) {
        _initializeThis(
            _yVault,
            _strategyName,
            _ilk,
            _gemJoin,
            _wantToUSDOSMProxy,
            _chainlinkWantToUSDPriceFeed,
            _chainlinkWantToETHPriceFeed
        );
    }

    function initialize(
        address _vault,
        address _yVault,
        string memory _strategyName,
        bytes32 _ilk,
        address _gemJoin,
        address _wantToUSDOSMProxy,
        address _chainlinkWantToUSDPriceFeed,
        address _chainlinkWantToETHPriceFeed
    ) public {
        // Make sure we only initialize one time
        require(address(yVault) == address(0)); // dev: strategy already initialized

        address sender = msg.sender;

        // Initialize BaseStrategy
        _initialize(_vault, sender, sender, sender);

        // Initialize cloned instance
        _initializeThis(
            _yVault,
            _strategyName,
            _ilk,
            _gemJoin,
            _wantToUSDOSMProxy,
            _chainlinkWantToUSDPriceFeed,
            _chainlinkWantToETHPriceFeed
        );
    }

    function _initializeThis(
        address _yVault,
        string memory _strategyName,
        bytes32 _ilk,
        address _gemJoin,
        address _wantToUSDOSMProxy,
        address _chainlinkWantToUSDPriceFeed,
        address _chainlinkWantToETHPriceFeed
    ) internal {
        yVault = IVault(_yVault);
        strategyName = _strategyName;
        ilk = _ilk;
        gemJoinAdapter = _gemJoin;
        wantToUSDOSMProxy = IOSMedianizer(_wantToUSDOSMProxy);
        chainlinkWantToUSDPriceFeed = AggregatorInterface(
            _chainlinkWantToUSDPriceFeed
        );
        chainlinkWantToETHPriceFeed = AggregatorInterface(
            _chainlinkWantToETHPriceFeed
        );

        // Set default router to SushiSwap
        router = sushiswapRouter;

        // Set health check to health.ychad.eth
        healthCheck = 0xDDCea799fF1699e98EDF118e0629A974Df7DF012;

        cdpId = MakerDaiDelegateLib.openCdp(ilk);
        require(cdpId > 0); // dev: error opening cdp

        // Current ratio can drift (collateralizationRatio - rebalanceTolerance, collateralizationRatio + rebalanceTolerance)
        // Allow additional 15% in any direction (210, 240) by default
        rebalanceTolerance = (15 * MAX_BPS) / 100;

        // Minimum collaterization ratio on YFI-A is 175%
        // Use 225% as target
        collateralizationRatio = (225 * MAX_BPS) / 100;

        // If we lose money in yvDAI then we are not OK selling want to repay it
        leaveDebtBehind = true;

        // Define maximum acceptable loss on withdrawal to be 0.01%.
        maxLoss = 1;
    }

    // ----------------- SETTERS & MIGRATION -----------------

    // Target collateralization ratio to maintain within bounds
    function setCollateralizationRatio(uint256 _collateralizationRatio)
        external
        onlyEmergencyAuthorized
    {
        require(
            _collateralizationRatio.sub(rebalanceTolerance) >
                MakerDaiDelegateLib.getLiquidationRatio(ilk).mul(MAX_BPS).div(
                    RAY
                )
        ); // dev: desired collateralization ratio is too low
        collateralizationRatio = _collateralizationRatio;
    }

    // Rebalancing bands (collat ratio - tolerance, collat_ratio + tolerance)
    function setRebalanceTolerance(uint256 _rebalanceTolerance)
        external
        onlyEmergencyAuthorized
    {
        require(
            collateralizationRatio.sub(_rebalanceTolerance) >
                MakerDaiDelegateLib.getLiquidationRatio(ilk).mul(MAX_BPS).div(
                    RAY
                )
        ); // dev: desired rebalance tolerance makes allowed ratio too low
        rebalanceTolerance = _rebalanceTolerance;
    }

    // Max slippage to accept when withdrawing from yVault
    function setMaxLoss(uint256 _maxLoss) external onlyVaultManagers {
        require(_maxLoss <= MAX_LOSS_BPS); // dev: invalid value for max loss
        maxLoss = _maxLoss;
    }

    // If set to true the strategy will never sell want to repay debts
    function setLeaveDebtBehind(bool _leaveDebtBehind)
        external
        onlyEmergencyAuthorized
    {
        leaveDebtBehind = _leaveDebtBehind;
    }

    // Required to move funds to a new cdp and use a different cdpId after migration
    // Should only be called by governance as it will move funds
    function shiftToCdp(uint256 newCdpId) external onlyGovernance {
        MakerDaiDelegateLib.shiftCdp(cdpId, newCdpId);
        cdpId = newCdpId;
    }

    // Move yvDAI funds to a new yVault
    function migrateToNewDaiYVault(IVault newYVault) external onlyGovernance {
        uint256 balanceOfYVault = yVault.balanceOf(address(this));
        if (balanceOfYVault > 0) {
            yVault.withdraw(balanceOfYVault, address(this), maxLoss);
        }
        investmentToken.safeApprove(address(yVault), 0);

        yVault = newYVault;
        _depositInvestmentTokenInYVault();
    }

    // Allow address to manage Maker's CDP
    function grantCdpManagingRightsToUser(address user, bool allow)
        external
        onlyGovernance
    {
        MakerDaiDelegateLib.allowManagingCdp(cdpId, user, allow);
    }

    // Allow switching between Uniswap and SushiSwap
    function switchDex(bool isUniswap) external onlyVaultManagers {
        if (isUniswap) {
            router = uniswapRouter;
        } else {
            router = sushiswapRouter;
        }
    }

    // ******** OVERRIDEN METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        return strategyName;
    }

    function delegatedAssets() external view override returns (uint256) {
        return _convertInvestmentTokenToWant(_valueOfInvestment());
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return
            balanceOfWant()
                .add(balanceOfMakerVault())
                .add(_convertInvestmentTokenToWant(balanceOfInvestmentToken()))
                .add(_convertInvestmentTokenToWant(_valueOfInvestment()))
                .sub(_convertInvestmentTokenToWant(balanceOfDebt()));
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

        // Claim rewards from yVault
        _takeYVaultProfit();

        uint256 totalAssetsAfterProfit = estimatedTotalAssets();

        _profit = totalAssetsAfterProfit > totalDebt
            ? totalAssetsAfterProfit.sub(totalDebt)
            : 0;

        uint256 _amountFreed;
        (_amountFreed, _loss) = liquidatePosition(
            _debtOutstanding.add(_profit)
        );
        _debtPayment = Math.min(_debtOutstanding, _amountFreed);

        if (_loss > _profit) {
            // Example:
            // debtOutstanding 100, profit 50, _amountFreed 100, _loss 50
            // loss should be 0, (50-50)
            // profit should endup in 0
            _loss = _loss.sub(_profit);
            _profit = 0;
        } else {
            // Example:
            // debtOutstanding 100, profit 50, _amountFreed 140, _loss 10
            // _profit should be 40, (50 profit - 10 loss)
            // loss should end up in be 0
            _profit = _profit.sub(_loss);
            _loss = 0;
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        MakerDaiDelegateLib.keepBasicMakerHygiene(ilk);

        // If we have enough want to deposit more into the maker vault, we do it
        // Do not skip the rest of the function as it may need to repay or take on more debt
        uint256 wantBalance = balanceOfWant();
        if (wantBalance > _debtOutstanding) {
            uint256 amountToDeposit = wantBalance.sub(_debtOutstanding);
            _depositToMakerVault(amountToDeposit);
        }

        // Allow the ratio to move a bit in either direction to avoid cycles
        uint256 currentRatio = getCurrentMakerVaultRatio();
        if (currentRatio < collateralizationRatio.sub(rebalanceTolerance)) {
            _repayDebt(currentRatio);
        } else if (
            currentRatio > collateralizationRatio.add(rebalanceTolerance)
        ) {
            _mintMoreInvestmentToken();
        }

        // If we have anything left to invest then deposit into the yVault
        _depositInvestmentTokenInYVault();
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 balance = balanceOfWant();

        // Check if we can handle it without freeing collateral
        if (balance >= _amountNeeded) {
            return (_amountNeeded, 0);
        }

        // We only need to free the amount of want not readily available
        uint256 amountToFree = _amountNeeded.sub(balance);

        uint256 price = _getWantTokenPrice();
        uint256 collateralBalance = balanceOfMakerVault();

        // We cannot free more than what we have locked
        amountToFree = Math.min(amountToFree, collateralBalance);

        uint256 totalDebt = balanceOfDebt();

        // If for some reason we do not have debt, make sure the operation does not revert
        if (totalDebt == 0) {
            totalDebt = 1;
        }

        uint256 toFreeIT = amountToFree.mul(price).div(WAD);
        uint256 collateralIT = collateralBalance.mul(price).div(WAD);
        uint256 newRatio =
            collateralIT.sub(toFreeIT).mul(MAX_BPS).div(totalDebt);

        // Attempt to repay necessary debt to restore the target collateralization ratio
        _repayDebt(newRatio);

        // Unlock as much collateral as possible while keeping the target ratio
        amountToFree = Math.min(amountToFree, _maxWithdrawal());
        _freeCollateralAndRepayDai(amountToFree, 0);

        // If we still need more want to repay, we may need to unlock some collateral to sell
        if (
            !leaveDebtBehind &&
            balanceOfWant() < _amountNeeded &&
            balanceOfDebt() > 0
        ) {
            _sellCollateralToRepayRemainingDebtIfNeeded();
        }

        uint256 looseWant = balanceOfWant();
        if (_amountNeeded > looseWant) {
            _liquidatedAmount = looseWant;
            _loss = _amountNeeded.sub(looseWant);
        } else {
            _liquidatedAmount = _amountNeeded;
            _loss = 0;
        }
    }

    function liquidateAllPositions()
        internal
        override
        returns (uint256 _amountFreed)
    {
        (_amountFreed, ) = liquidatePosition(estimatedTotalAssets());
    }

    function tendTrigger(uint256 callCostInWei)
        public
        view
        override
        returns (bool)
    {
        // Nothing to adjust if there is no collateral locked
        if (balanceOfMakerVault() == 0) {
            return false;
        }

        uint256 currentRatio = getCurrentMakerVaultRatio();

        // If we need to repay debt and are outside the tolerance bands,
        // we do it regardless of the call cost
        if (currentRatio < collateralizationRatio.sub(rebalanceTolerance)) {
            return true;
        }

        // If we could mint more DAI, check that there is DAI available to mint
        // Otherwise do not adjust the position
        return
            (currentRatio > collateralizationRatio.add(rebalanceTolerance)) &&
            MakerDaiDelegateLib.isDaiAvailableToMint(ilk);
    }

    function prepareMigration(address _newStrategy) internal override {
        // Transfer Maker Vault ownership to the new startegy
        MakerDaiDelegateLib.transferCdp(cdpId, _newStrategy);

        // Move yvDAI balance to the new strategy
        IERC20(yVault).safeTransfer(
            _newStrategy,
            yVault.balanceOf(address(this))
        );
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](2);
        protected[0] = address(investmentToken);
        protected[1] = address(yVault);
        return protected;
    }

    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        if (address(want) == address(WETH)) {
            return _amtInWei;
        }

        uint256 price = uint256(chainlinkWantToETHPriceFeed.latestAnswer());
        return _amtInWei.mul(WAD).div(price);
    }

    // ----------------- INTERNAL FUNCTIONS SUPPORT -----------------

    function _repayDebt(uint256 currentRatio) internal {
        uint256 currentDebt = balanceOfDebt();

        // Nothing to repay if we are over the collateralization ratio
        // or there is no debt
        if (currentRatio > collateralizationRatio || currentDebt == 0) {
            return;
        }

        // ratio = collateral / debt
        // collateral = current_ratio * current_debt
        // collateral amount is invariant here so we want to find new_debt
        // so that new_debt * desired_ratio = current_debt * current_ratio
        // new_debt = current_debt * current_ratio / desired_ratio
        // and the amount to repay is the difference between current_debt and new_debt
        uint256 newDebt =
            currentDebt.mul(currentRatio).div(collateralizationRatio);

        uint256 amountToRepay;

        // Maker will revert if the outstanding debt is less than a debt floor
        // called 'dust'. If we are there we need to either pay the debt in full
        // or leave at least 'dust' balance (10,000 DAI for YFI-A)
        uint256 debtFloor = MakerDaiDelegateLib.debtFloor(ilk);
        if (newDebt <= debtFloor) {
            // If we sold want to repay debt we will have DAI readily available in the strategy
            // This means we need to count both yvDAI shares and current DAI balance
            uint256 totalInvestmentAvailableToRepay =
                _valueOfInvestment().add(balanceOfInvestmentToken());

            if (totalInvestmentAvailableToRepay >= currentDebt) {
                // Pay the entire debt if we have enough investment token
                amountToRepay = currentDebt;
            } else {
                // Pay just 0.1 cent above debtFloor (best effort without liquidating want)
                amountToRepay = currentDebt.sub(debtFloor).sub(1e15);
            }
        } else {
            // If we are not near the debt floor then just pay the exact amount
            // needed to obtain a healthy collateralization ratio
            amountToRepay = currentDebt.sub(newDebt);
        }

        uint256 balanceIT = balanceOfInvestmentToken();
        if (amountToRepay > balanceIT) {
            _withdrawFromYVault(amountToRepay.sub(balanceIT));
        }
        _repayInvestmentTokenDebt(amountToRepay);
    }

    function _sellCollateralToRepayRemainingDebtIfNeeded() internal {
        uint256 currentInvestmentValue = _valueOfInvestment();

        uint256 investmentLeftToAcquire =
            balanceOfDebt().sub(currentInvestmentValue);

        uint256 investmentLeftToAcquireInWant =
            _convertInvestmentTokenToWant(investmentLeftToAcquire);

        if (investmentLeftToAcquireInWant <= balanceOfWant()) {
            _buyInvestmentTokenWithWant(investmentLeftToAcquire);
            _repayDebt(0);
            _freeCollateralAndRepayDai(balanceOfMakerVault(), 0);
        }
    }

    // Mint the maximum DAI possible for the locked collateral
    function _mintMoreInvestmentToken() internal {
        uint256 price = _getWantTokenPrice();
        uint256 amount = balanceOfMakerVault();

        uint256 daiToMint =
            amount.mul(price).mul(MAX_BPS).div(collateralizationRatio).div(WAD);
        daiToMint = daiToMint.sub(balanceOfDebt());
        _lockCollateralAndMintDai(0, daiToMint);
    }

    function _withdrawFromYVault(uint256 _amountIT) internal returns (uint256) {
        if (_amountIT == 0) {
            return 0;
        }
        // No need to check allowance because the contract == token
        uint256 balancePrior = balanceOfInvestmentToken();
        uint256 sharesToWithdraw =
            Math.min(
                _investmentTokenToYShares(_amountIT),
                yVault.balanceOf(address(this))
            );
        if (sharesToWithdraw == 0) {
            return 0;
        }
        yVault.withdraw(sharesToWithdraw, address(this), maxLoss);
        return balanceOfInvestmentToken().sub(balancePrior);
    }

    function _depositInvestmentTokenInYVault() internal {
        uint256 balanceIT = balanceOfInvestmentToken();
        if (balanceIT > 0) {
            _checkAllowance(
                address(yVault),
                address(investmentToken),
                balanceIT
            );

            yVault.deposit();
        }
    }

    function _repayInvestmentTokenDebt(uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        uint256 debt = balanceOfDebt();
        uint256 balanceIT = balanceOfInvestmentToken();

        // We cannot pay more than loose balance
        amount = Math.min(amount, balanceIT);

        // We cannot pay more than we owe
        amount = Math.min(amount, debt);

        _checkAllowance(
            MakerDaiDelegateLib.daiJoinAddress(),
            address(investmentToken),
            amount
        );

        if (amount > 0) {
            // When repaying the full debt it is very common to experience Vat/dust
            // reverts due to the debt being non-zero and less than the debt floor.
            // This can happen due to rounding when _wipeAndFreeGem() divides
            // the DAI amount by the accumulated stability fee rate.
            // To circumvent this issue we will add 1 Wei to the amount to be paid
            // if there is enough investment token balance (DAI) to do it.
            if (debt.sub(amount) == 0 && balanceIT.sub(amount) >= 1) {
                amount = amount.add(1);
            }

            // Repay debt amount without unlocking collateral
            _freeCollateralAndRepayDai(0, amount);
        }
    }

    function _checkAllowance(
        address _contract,
        address _token,
        uint256 _amount
    ) internal {
        if (IERC20(_token).allowance(address(this), _contract) < _amount) {
            IERC20(_token).safeApprove(_contract, 0);
            IERC20(_token).safeApprove(_contract, type(uint256).max);
        }
    }

    function _takeYVaultProfit() internal {
        uint256 _debt = balanceOfDebt();
        uint256 _valueInVault = _valueOfInvestment();
        if (_debt >= _valueInVault) {
            return;
        }

        uint256 profit = _valueInVault.sub(_debt);
        uint256 ySharesToWithdraw = _investmentTokenToYShares(profit);
        if (ySharesToWithdraw > 0) {
            yVault.withdraw(ySharesToWithdraw, address(this), maxLoss);
            _sellAForB(
                balanceOfInvestmentToken(),
                address(investmentToken),
                address(want)
            );
        }
    }

    function _depositToMakerVault(uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        _checkAllowance(gemJoinAdapter, address(want), amount);

        uint256 price = _getWantTokenPrice();
        uint256 daiToMint =
            amount.mul(price).mul(MAX_BPS).div(collateralizationRatio).div(WAD);

        _lockCollateralAndMintDai(amount, daiToMint);
    }

    // Returns maximum collateral to withdraw while maintaining the target collateralization ratio
    function _maxWithdrawal() internal view returns (uint256) {
        // Denominated in want
        uint256 totalCollateral = balanceOfMakerVault();

        // Denominated in investment token
        uint256 totalDebt = balanceOfDebt();

        // If there is no debt to repay we can withdraw all the locked collateral
        if (totalDebt == 0) {
            return totalCollateral;
        }

        uint256 price = _getWantTokenPrice();

        // Min collateral in want that needs to be locked with the outstanding debt
        // Allow going to the lower rebalancing band
        uint256 minCollateral =
            collateralizationRatio
                .sub(rebalanceTolerance)
                .mul(totalDebt)
                .mul(WAD)
                .div(price)
                .div(MAX_BPS);

        // If we are under collateralized then it is not safe for us to withdraw anything
        if (minCollateral > totalCollateral) {
            return 0;
        }

        return totalCollateral.sub(minCollateral);
    }

    // ----------------- PUBLIC BALANCES -----------------

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfInvestmentToken() public view returns (uint256) {
        return investmentToken.balanceOf(address(this));
    }

    function balanceOfDebt() public view returns (uint256) {
        return MakerDaiDelegateLib.debtForCdp(cdpId, ilk);
    }

    // Returns collateral balance in the vault
    function balanceOfMakerVault() public view returns (uint256) {
        return MakerDaiDelegateLib.balanceOfCdp(cdpId, ilk);
    }

    // Effective collateralization ratio of the vault
    function getCurrentMakerVaultRatio() public view returns (uint256) {
        return
            MakerDaiDelegateLib.getPessimisticRatioOfCdpWithExternalPrice(
                cdpId,
                ilk,
                _getWantTokenPrice(),
                MAX_BPS
            );
    }

    // ----------------- INTERNAL CALCS -----------------

    function _getWantTokenPrice() internal view returns (uint256) {
        uint256 minPrice;

        // Assume we are white-listed in the OSM
        (uint256 current, ) = wantToUSDOSMProxy.read();
        (uint256 future, ) = wantToUSDOSMProxy.foresight();

        minPrice = Math.min(future, current);

        // Non-ETH pairs have 8 decimals, so we need to adjust it to 18
        uint256 chainLinkPrice =
            uint256(chainlinkWantToUSDPriceFeed.latestAnswer()).mul(1e10);

        // Return the worst price available in [wad]
        // par is crucial to this calculation as it defines the relationship between DAI and
        // 1 unit of value in the price
        minPrice = Math.min(minPrice, chainLinkPrice).mul(RAY).div(
            MakerDaiDelegateLib.getDaiPar()
        );

        // If peek() or peep() return a price of 0 or an error then we are
        // dealing with an invalid price or Maker Protocol Emergency Shutdown
        require(minPrice > 0); // dev: invalid price returned from oracle
        return minPrice;
    }

    function _valueOfInvestment() internal view returns (uint256) {
        return
            yVault.balanceOf(address(this)).mul(yVault.pricePerShare()).div(
                10**yVault.decimals()
            );
    }

    function _investmentTokenToYShares(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount.mul(10**yVault.decimals()).div(yVault.pricePerShare());
    }

    function _lockCollateralAndMintDai(
        uint256 collateralAmount,
        uint256 daiToMint
    ) internal {
        MakerDaiDelegateLib.lockGemAndDraw(
            gemJoinAdapter,
            cdpId,
            collateralAmount,
            daiToMint,
            balanceOfDebt()
        );
    }

    function _freeCollateralAndRepayDai(
        uint256 collateralAmount,
        uint256 daiToRepay
    ) internal {
        MakerDaiDelegateLib.wipeAndFreeGem(
            gemJoinAdapter,
            cdpId,
            collateralAmount,
            daiToRepay
        );
    }

    // ----------------- TOKEN CONVERSIONS -----------------

    function _convertInvestmentTokenToWant(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount.mul(WAD).div(_getWantTokenPrice());
    }

    function _getTokenOutPath(address _token_in, address _token_out)
        internal
        pure
        returns (address[] memory _path)
    {
        bool is_weth =
            _token_in == address(WETH) || _token_out == address(WETH);
        _path = new address[](is_weth ? 2 : 3);
        _path[0] = _token_in;

        if (is_weth) {
            _path[1] = _token_out;
        } else {
            _path[1] = address(WETH);
            _path[2] = _token_out;
        }
    }

    function _sellAForB(
        uint256 _amount,
        address tokenA,
        address tokenB
    ) internal {
        if (_amount == 0 || tokenA == tokenB) {
            return;
        }

        _checkAllowance(address(router), tokenA, _amount);
        router.swapExactTokensForTokens(
            _amount,
            0,
            _getTokenOutPath(tokenA, tokenB),
            address(this),
            now
        );
    }


    function _buyInvestmentTokenWithWant(uint256 _amount) internal {
        // SWC-135-Code With No Effects: L857
        if (_amount == 0 || address(investmentToken) == address(want)) {
            return;
        }

        _checkAllowance(address(router), address(want), _amount);
        router.swapTokensForExactTokens(
            _amount,
            type(uint256).max,
            _getTokenOutPath(address(want), address(investmentToken)),
            address(this),
            now
        );
    }
}
