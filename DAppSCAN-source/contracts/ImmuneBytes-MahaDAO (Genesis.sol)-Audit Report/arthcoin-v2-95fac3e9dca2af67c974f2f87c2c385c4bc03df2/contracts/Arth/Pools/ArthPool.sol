// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {IARTH} from '../IARTH.sol';
import {IARTHPool} from './IARTHPool.sol';
import {IERC20} from '../../ERC20/IERC20.sol';
import {IARTHX} from '../../ARTHX/IARTHX.sol';
import {ICurve} from '../../Curves/ICurve.sol';
import {SafeMath} from '../../utils/math/SafeMath.sol';
import {ArthPoolLibrary} from './ArthPoolLibrary.sol';
import {IARTHController} from '../IARTHController.sol';
import {ISimpleOracle} from '../../Oracle/ISimpleOracle.sol';
import {IERC20Burnable} from '../../ERC20/IERC20Burnable.sol';
import {AccessControl} from '../../access/AccessControl.sol';
import {IUniswapPairOracle} from '../../Oracle/IUniswapPairOracle.sol';

/**
 * @title  ARTHPool.
 * @author MahaDAO.
 *
 *  Original code written by:
 *  - Travis Moore, Jason Huan, Same Kazemian, Sam Sun.
 */
contract ArthPool is AccessControl, IARTHPool {
    using SafeMath for uint256;

    /**
     * @dev Contract instances.
     */

    IARTH private _ARTH;
    IARTHX private _ARTHX;
    IERC20 private _COLLATERAL;
    IERC20Burnable private _MAHA;
    ISimpleOracle private _ARTHMAHAOracle;
    IARTHController private _arthController;
    ICurve private _recollateralizeDiscountCruve;
    IUniswapPairOracle private _collateralETHOracle;

    bool public mintPaused = false;
    bool public redeemPaused = false;
    bool public buyBackPaused = false;
    bool public recollateralizePaused = false;
    bool public override collateralPricePaused = false;

    uint256 public override buybackFee;
    uint256 public override mintingFee;
    uint256 public override recollatFee;
    uint256 public override redemptionFee;
    uint256 public stabilityFee = 1; // In %.
    uint256 public buybackCollateralBuffer = 20; // In %.

    uint256 public override pausedPrice = 0; // Stores price of the collateral, if price is paused
    uint256 public poolCeiling = 0; // Total units of collateral that a pool contract can hold
    uint256 public redemptionDelay = 1; // Number of blocks to wait before being able to collect redemption.

    uint256 public unclaimedPoolARTHX;
    uint256 public unclaimedPoolCollateral;

    address public override collateralETHOracleAddress;

    mapping(address => uint256) public lastRedeemed;
    mapping(address => uint256) public borrowedCollateral;
    mapping(address => uint256) public redeemARTHXBalances;
    mapping(address => uint256) public redeemCollateralBalances;

    bytes32 private constant _RECOLLATERALIZE_PAUSER =
        keccak256('RECOLLATERALIZE_PAUSER');
    bytes32 private constant _COLLATERAL_PRICE_PAUSER =
        keccak256('COLLATERAL_PRICE_PAUSER');
    bytes32 private constant _AMO_ROLE = keccak256('AMO_ROLE');
    bytes32 private constant _MINT_PAUSER = keccak256('MINT_PAUSER');
    bytes32 private constant _REDEEM_PAUSER = keccak256('REDEEM_PAUSER');
    bytes32 private constant _BUYBACK_PAUSER = keccak256('BUYBACK_PAUSER');

    uint256 private immutable _missingDeciamls;
    uint256 private constant _PRICE_PRECISION = 1e6;
    uint256 private constant _COLLATERAL_RATIO_MAX = 1e6;
    uint256 private constant _COLLATERAL_RATIO_PRECISION = 1e6;

    address private _wethAddress;
    address private _ownerAddress;
    address private _timelockAddress;
    address private _collateralAddress;
    address private _arthContractAddress;
    address private _arthxContractAddress;

    /**
     * Events.
     */
    event Repay(address indexed from, uint256 amount);
    event Borrow(address indexed from, uint256 amount);
    event StabilityFeesCharged(address indexed from, uint256 fee);

    /**
     * Modifiers.
     */
    modifier onlyByOwnerOrGovernance() {
        require(
            msg.sender == _timelockAddress || msg.sender == _ownerAddress,
            'ArthPool: You are not the owner or the governance timelock'
        );
        _;
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            'ArthPool: You are not the admin'
        );
        _;
    }

    modifier onlyAdminOrOwnerOrGovernance() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) ||
                msg.sender == _timelockAddress ||
                msg.sender == _ownerAddress,
            'ArthPool: forbidden'
        );
        _;
    }

    modifier onlyAMOS {
        require(hasRole(_AMO_ROLE, _msgSender()), 'ArthPool: forbidden');
        _;
    }

    modifier notRedeemPaused() {
        require(redeemPaused == false, 'ArthPool: Redeeming is paused');
        _;
    }

    modifier notMintPaused() {
        require(mintPaused == false, 'ArthPool: Minting is paused');
        _;
    }

    /**
     * Constructor.
     */

    constructor(
        address __arthContractAddress,
        address __arthxContractAddress,
        address __collateralAddress,
        address _creatorAddress,
        address __timelockAddress,
        address __MAHA,
        address __ARTHMAHAOracle,
        address __arthController,
        uint256 _poolCeiling
    ) {
        _MAHA = IERC20Burnable(__MAHA);
        _ARTH = IARTH(__arthContractAddress);
        _COLLATERAL = IERC20(__collateralAddress);
        _ARTHX = IARTHX(__arthxContractAddress);
        _ARTHMAHAOracle = ISimpleOracle(__ARTHMAHAOracle);
        _arthController = IARTHController(__arthController);

        _ownerAddress = _creatorAddress;
        _timelockAddress = __timelockAddress;
        _collateralAddress = __collateralAddress;
        _arthContractAddress = __arthContractAddress;
        _arthxContractAddress = __arthxContractAddress;

        poolCeiling = _poolCeiling;
        _missingDeciamls = uint256(18).sub(_COLLATERAL.decimals());

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        grantRole(_MINT_PAUSER, _timelockAddress);
        grantRole(_REDEEM_PAUSER, _timelockAddress);
        grantRole(_BUYBACK_PAUSER, _timelockAddress);
        grantRole(_RECOLLATERALIZE_PAUSER, _timelockAddress);
        grantRole(_COLLATERAL_PRICE_PAUSER, _timelockAddress);
    }

    /**
     * External.
     */
    function setBuyBackCollateralBuffer(uint256 percent)
        external
        override
        onlyAdminOrOwnerOrGovernance
    {
        require(percent <= 100, 'ArthPool: percent > 100');
        buybackCollateralBuffer = percent;
    }

    function setRecollateralizationCurve(ICurve curve)
        external
        onlyAdminOrOwnerOrGovernance
    {
        _recollateralizeDiscountCruve = curve;
    }

    function setStabilityFee(uint256 percent)
        external
        override
        onlyAdminOrOwnerOrGovernance
    {
        require(percent <= 100, 'ArthPool: percent > 100');

        stabilityFee = percent;
    }

    function setCollatETHOracle(
        address _collateralWETHOracleAddress,
        address __wethAddress
    ) external override onlyByOwnerOrGovernance {
        collateralETHOracleAddress = _collateralWETHOracleAddress;
        _collateralETHOracle = IUniswapPairOracle(_collateralWETHOracleAddress);
        _wethAddress = __wethAddress;
    }

    function toggleMinting() external override {
        require(hasRole(_MINT_PAUSER, msg.sender));
        mintPaused = !mintPaused;
    }

    function toggleRedeeming() external override {
        require(hasRole(_REDEEM_PAUSER, msg.sender));
        redeemPaused = !redeemPaused;
    }

    function toggleRecollateralize() external override {
        require(hasRole(_RECOLLATERALIZE_PAUSER, msg.sender));
        recollateralizePaused = !recollateralizePaused;
    }

    function toggleBuyBack() external override {
        require(hasRole(_BUYBACK_PAUSER, msg.sender));
        buyBackPaused = !buyBackPaused;
    }

    function toggleCollateralPrice(uint256 newPrice) external override {
        require(hasRole(_COLLATERAL_PRICE_PAUSER, msg.sender));

        // If pausing, set paused price; else if unpausing, clear pausedPrice.
        if (collateralPricePaused == false) pausedPrice = newPrice;
        else pausedPrice = 0;

        collateralPricePaused = !collateralPricePaused;
    }

    // Combined into one function due to 24KiB contract memory limit
    function setPoolParameters(
        uint256 newCeiling,
        uint256 newRedemptionDelay,
        uint256 newMintFee,
        uint256 newRedeemFee,
        uint256 newBuybackFee,
        uint256 newRecollateralizeFee
    ) external override onlyByOwnerOrGovernance {
        poolCeiling = newCeiling;
        redemptionDelay = newRedemptionDelay;
        mintingFee = newMintFee;
        redemptionFee = newRedeemFee;
        buybackFee = newBuybackFee;
        recollatFee = newRecollateralizeFee;
    }

    function setTimelock(address new_timelock)
        external
        override
        onlyByOwnerOrGovernance
    {
        _timelockAddress = new_timelock;
    }

    function setOwner(address __ownerAddress)
        external
        override
        onlyByOwnerOrGovernance
    {
        _ownerAddress = __ownerAddress;
    }

    function borrow(uint256 _amount) external override onlyAMOS {
        require(
            _COLLATERAL.balanceOf(address(this)) > _amount,
            'ArthPool: Insufficent funds in the pool'
        );

        _COLLATERAL.transfer(msg.sender, _amount);
        borrowedCollateral[msg.sender] += _amount;

        emit Borrow(msg.sender, _amount);
    }

    function repay(uint256 amount) external override onlyAMOS {
        require(
            borrowedCollateral[msg.sender] > 0,
            "ArthPool: Repayer doesn't not have any debt"
        );

        require(
            _COLLATERAL.balanceOf(msg.sender) >= amount,
            'ArthPool: balance < required'
        );
        _COLLATERAL.transferFrom(msg.sender, address(this), amount);

        borrowedCollateral[msg.sender] -= amount;

        emit Repay(msg.sender, amount);
    }

    function mint1t1ARTH(uint256 collateralAmount, uint256 arthOutMin)
        external
        override
        notMintPaused
        returns (uint256)
    {
        uint256 collateralAmountD18 = collateralAmount * (10**_missingDeciamls);

        require(
            _arthController.getCRForMint() >= _COLLATERAL_RATIO_MAX,
            'ARHTPool: Collateral ratio < 1'
        );
        require(
            (_COLLATERAL.balanceOf(address(this)))
                .sub(unclaimedPoolCollateral)
                .add(collateralAmount) <= poolCeiling,
            'ARTHPool: ceiling reached'
        );

        // 1 ARTH for each $1 worth of collateral.
        uint256 arthAmountD18 =
            ArthPoolLibrary.calcMint1t1ARTH(
                getCollateralPrice(),
                collateralAmountD18
            );

        // Remove precision at the end.
        arthAmountD18 = (arthAmountD18.mul(uint256(1e6).sub(mintingFee))).div(
            1e6
        );

        require(
            arthOutMin <= arthAmountD18,
            'ARTHPool: Slippage limit reached'
        );

        require(
            _COLLATERAL.balanceOf(msg.sender) >= collateralAmount,
            'ArthPool: balance < required'
        );
        _COLLATERAL.transferFrom(msg.sender, address(this), collateralAmount);

        _ARTH.poolMint(msg.sender, arthAmountD18);

        return arthAmountD18;
    }

    function mintAlgorithmicARTH(uint256 arthxAmountD18, uint256 arthOutMin)
        external
        override
        notMintPaused
        returns (uint256)
    {
        uint256 arthxPrice = _arthController.getARTHXPrice();

        require(_arthController.getCRForMint() == 0, 'ARTHPool: Collateral ratio != 0');

        uint256 arthAmountD18 =
            ArthPoolLibrary.calcMintAlgorithmicARTH(
                arthxPrice, // X ARTHX / 1 USD
                arthxAmountD18
            );
        arthAmountD18 = (arthAmountD18.mul(uint256(1e6).sub(mintingFee))).div(
            1e6
        );

        require(arthOutMin <= arthAmountD18, 'Slippage limit reached');

        _ARTH.poolMint(msg.sender, arthAmountD18);
        _ARTHX.poolBurnFrom(msg.sender, arthxAmountD18);

        return arthAmountD18;
    }

    // Will fail if fully collateralized or fully algorithmic
    // > 0% and < 100% collateral-backed
    function mintFractionalARTH(
        uint256 collateralAmount,
        uint256 arthxAmount,
        uint256 arthOutMin
    ) external override notMintPaused returns (uint256) {
        uint256 arthxPrice = _arthController.getARTHXPrice();
        uint256 collateralRatioForMint = _arthController.getCRForMint();

        require(
            collateralRatioForMint < _COLLATERAL_RATIO_MAX &&
                collateralRatioForMint > 0,
            'ARTHPool: fails (.000001 <= Collateral ratio <= .999999)'
        );

        require(
            _COLLATERAL
                .balanceOf(address(this))
                .sub(unclaimedPoolCollateral)
                .add(collateralAmount) <= poolCeiling,
            'ARTHPool: ceiling reached.'
        );

        uint256 collateralAmountD18 = collateralAmount * (10**_missingDeciamls);
        ArthPoolLibrary.MintFAParams memory inputParams =
            ArthPoolLibrary.MintFAParams(
                arthxPrice,
                getCollateralPrice(),
                arthxAmount,
                collateralAmountD18,
                collateralRatioForMint
            );

        (uint256 mintAmount, uint256 arthxNeeded) =
            ArthPoolLibrary.calcMintFractionalARTH(inputParams);

        mintAmount = (mintAmount.mul(uint256(1e6).sub(mintingFee))).div(1e6);

        require(arthOutMin <= mintAmount, 'ARTHPool: Slippage limit reached');
        require(arthxNeeded <= arthxAmount, 'ARTHPool: ARTHX < required');

        _ARTHX.poolBurnFrom(msg.sender, arthxNeeded);

        require(
            _COLLATERAL.balanceOf(msg.sender) >= collateralAmount,
            'ArthPool: balance < require'
        );
        _COLLATERAL.transferFrom(msg.sender, address(this), collateralAmount);

        _ARTH.poolMint(msg.sender, mintAmount);

        return mintAmount;
    }

    // Redeem collateral. 100% collateral-backed
    function redeem1t1ARTH(uint256 arthAmount, uint256 collateralOutMin)
        external
        override
        notRedeemPaused
    {
        require(
            _arthController.getCRForRedeem() == _COLLATERAL_RATIO_MAX,
            'Collateral ratio must be == 1'
        );

        // Need to adjust for decimals of collateral
        uint256 arthAmountPrecision = arthAmount.div(10**_missingDeciamls);
        uint256 collateralNeeded =
            ArthPoolLibrary.calcRedeem1t1ARTH(
                getCollateralPrice(),
                arthAmountPrecision
            );

        collateralNeeded = (
            collateralNeeded.mul(uint256(1e6).sub(redemptionFee))
        )
            .div(1e6);

        require(
            collateralNeeded <=
                _COLLATERAL.balanceOf(address(this)).sub(
                    unclaimedPoolCollateral
                ),
            'ARTHPool: Not enough collateral in pool'
        );
        require(
            collateralOutMin <= collateralNeeded,
            'ARTHPool: Slippage limit reached'
        );

        redeemCollateralBalances[msg.sender] = redeemCollateralBalances[
            msg.sender
        ]
            .add(collateralNeeded);
        unclaimedPoolCollateral = unclaimedPoolCollateral.add(collateralNeeded);
        lastRedeemed[msg.sender] = block.number;

        _chargeStabilityFee(arthAmount);

        // Move all external functions to the end
        _ARTH.poolBurnFrom(msg.sender, arthAmount);
    }

    // Will fail if fully collateralized or algorithmic
    // Redeem ARTH for collateral and ARTHX. > 0% and < 100% collateral-backed
    function redeemFractionalARTH(
        uint256 arthAmount,
        uint256 arthxOutMin,
        uint256 collateralOutMin
    ) external override notRedeemPaused {
        uint256 arthxPrice = _arthController.getARTHXPrice();
        uint256 collateralRatioForRedeem = _arthController.getCRForRedeem();

        require(
            collateralRatioForRedeem < _COLLATERAL_RATIO_MAX &&
                collateralRatioForRedeem > 0,
            'ARTHPool: Collateral ratio needs to be between .000001 and .999999'
        );

        uint256 collateralPriceGMU = getCollateralPrice();
        uint256 arthAmountPostFee =
            (arthAmount.mul(uint256(1e6).sub(redemptionFee))).div(
                _PRICE_PRECISION
            );

        uint256 arthxGMUValueD18 =
            arthAmountPostFee.sub(
                arthAmountPostFee.mul(collateralRatioForRedeem).div(
                    _PRICE_PRECISION
                )
            );
        uint256 arthxAmount =
            arthxGMUValueD18.mul(_PRICE_PRECISION).div(arthxPrice);

        // Need to adjust for decimals of collateral
        uint256 arthAmountPrecision =
            arthAmountPostFee.div(10**_missingDeciamls);
        uint256 collateralDollatValue =
            arthAmountPrecision.mul(collateralRatioForRedeem).div(
                _PRICE_PRECISION
            );
        uint256 collateralAmount =
            collateralDollatValue.mul(_PRICE_PRECISION).div(collateralPriceGMU);

        require(
            collateralAmount <=
                _COLLATERAL.balanceOf(address(this)).sub(
                    unclaimedPoolCollateral
                ),
            'Not enough collateral in pool'
        );
        require(
            collateralOutMin <= collateralAmount,
            'Slippage limit reached [collateral]'
        );
        require(arthxOutMin <= arthxAmount, 'Slippage limit reached [ARTHX]');

        redeemCollateralBalances[msg.sender] += collateralAmount;
        unclaimedPoolCollateral += collateralAmount;

        redeemARTHXBalances[msg.sender] += arthxAmount;
        unclaimedPoolARTHX += arthxAmount;

        lastRedeemed[msg.sender] = block.number;

        _chargeStabilityFee(arthAmount);

        // Move all external functions to the end
        _ARTH.poolBurnFrom(msg.sender, arthAmount);
        _ARTHX.poolMint(address(this), arthxAmount);
    }

    // Redeem ARTH for ARTHX. 0% collateral-backed
    function redeemAlgorithmicARTH(uint256 arthAmount, uint256 arthxOutMin)
        external
        override
        notRedeemPaused
    {
        uint256 arthxPrice = _arthController.getARTHXPrice();
        uint256 collateralRatioForRedeem = _arthController.getCRForRedeem();

        require(collateralRatioForRedeem == 0, 'Collateral ratio must be 0');
        uint256 arthxGMUValueD18 = arthAmount;

        arthxGMUValueD18 = (
            arthxGMUValueD18.mul(uint256(1e6).sub(redemptionFee))
        )
            .div(_PRICE_PRECISION); // apply fees

        uint256 arthxAmount =
            arthxGMUValueD18.mul(_PRICE_PRECISION).div(arthxPrice);

        redeemARTHXBalances[msg.sender] = redeemARTHXBalances[msg.sender].add(
            arthxAmount
        );
        unclaimedPoolARTHX += arthxAmount;

        lastRedeemed[msg.sender] = block.number;

        require(arthxOutMin <= arthxAmount, 'Slippage limit reached');

        _chargeStabilityFee(arthAmount);

        // Move all external functions to the end
        _ARTH.poolBurnFrom(msg.sender, arthAmount);
        _ARTHX.poolMint(address(this), arthxAmount);
    }

    // After a redemption happens, transfer the newly minted ARTHX and owed collateral from this pool
    // contract to the user. Redemption is split into two functions to prevent flash loans from being able
    // to take out ARTH/collateral from the system, use an AMM to trade the new price, and then mint back into the system.
    function collectRedemption() external override {
        require(
            (lastRedeemed[msg.sender].add(redemptionDelay)) <= block.number,
            'Must wait for redemptionDelay blocks before collecting redemption'
        );

        uint256 ARTHXAmount;
        uint256 CollateralAmount;
        bool sendARTHX = false;
        bool sendCollateral = false;

        // Use Checks-Effects-Interactions pattern
        if (redeemARTHXBalances[msg.sender] > 0) {
            ARTHXAmount = redeemARTHXBalances[msg.sender];
            redeemARTHXBalances[msg.sender] = 0;
            unclaimedPoolARTHX = unclaimedPoolARTHX.sub(ARTHXAmount);

            sendARTHX = true;
        }

        if (redeemCollateralBalances[msg.sender] > 0) {
            CollateralAmount = redeemCollateralBalances[msg.sender];
            redeemCollateralBalances[msg.sender] = 0;
            unclaimedPoolCollateral = unclaimedPoolCollateral.sub(
                CollateralAmount
            );

            sendCollateral = true;
        }

        if (sendARTHX == true) _ARTHX.transfer(msg.sender, ARTHXAmount);
        if (sendCollateral == true)
            _COLLATERAL.transfer(msg.sender, CollateralAmount);
    }

    // When the protocol is recollateralizing, we need to give a discount of ARTHX to hit the new CR target
    // Thus, if the target collateral ratio is higher than the actual value of collateral, minters get ARTHX for adding collateral
    // This function simply rewards anyone that sends collateral to a pool with the same amount of ARTHX + the bonus rate
    // Anyone can call this function to recollateralize the protocol and take the extra ARTHX value from the bonus rate as an arb opportunity
    function recollateralizeARTH(uint256 collateralAmount, uint256 arthxOutMin)
        external
        override
        returns (uint256)
    {
        require(recollateralizePaused == false, 'Recollateralize is paused');

        uint256 collateralAmountD18 = collateralAmount * (10**_missingDeciamls);
        uint256 arthxPrice = _arthController.getARTHXPrice();
        uint256 arthTotalSupply = _ARTH.totalSupply();
        uint256 collateralRatioForRecollateralize = _arthController.getCRForRecollateralize();
        uint256 globalCollatValue = _arthController.getGlobalCollateralValue();

        (uint256 collateralUnits, uint256 amountToRecollateralize) =
            ArthPoolLibrary.calcRecollateralizeARTHInner(
                collateralAmountD18,
                getCollateralPrice(),
                globalCollatValue,
                arthTotalSupply,
                collateralRatioForRecollateralize
            );

        uint256 collateralUnitsPrecision =
            collateralUnits.div(10**_missingDeciamls);

        // NEED to make sure that recollatFee is less than 1e6.
        uint256 arthxPaidBack =
            amountToRecollateralize
                .mul(
                uint256(1e6)
                    .add(getRecollateralizationDiscount())
                    .sub(recollatFee)
            )
                .div(arthxPrice);

        require(arthxOutMin <= arthxPaidBack, 'Slippage limit reached');
        require(
            _COLLATERAL.balanceOf(msg.sender) >= collateralUnitsPrecision,
            'ArthPool: balance < required'
        );
        _COLLATERAL.transferFrom(
            msg.sender,
            address(this),
            collateralUnitsPrecision
        );

        _ARTHX.poolMint(msg.sender, arthxPaidBack);

        return arthxPaidBack;
    }

    // Function can be called by an ARTHX holder to have the protocol buy back ARTHX with excess collateral value from a desired collateral pool
    // This can also happen if the collateral ratio > 1
    function buyBackARTHX(uint256 arthxAmount, uint256 collateralOutMin)
        external
        override
    {
        require(buyBackPaused == false, 'Buyback is paused');

        uint256 arthxPrice = _arthController.getARTHXPrice();

        ArthPoolLibrary.BuybackARTHXParams memory inputParams =
            ArthPoolLibrary.BuybackARTHXParams(
                getAvailableExcessCollateralDV(),
                arthxPrice,
                getCollateralPrice(),
                arthxAmount
            );

        uint256 collateralEquivalentD18 =
            (ArthPoolLibrary.calcBuyBackARTHX(inputParams))
                .mul(uint256(1e6).sub(buybackFee))
                .div(1e6);
        uint256 collateralPrecision =
            collateralEquivalentD18.div(10**_missingDeciamls);

        require(
            collateralOutMin <= collateralPrecision,
            'Slippage limit reached'
        );

        // Give the sender their desired collateral and burn the ARTHX
        _ARTHX.poolBurnFrom(msg.sender, arthxAmount);
        _COLLATERAL.transfer(msg.sender, collateralPrecision);
    }

    function getARTHMAHAPrice() public view override returns (uint256) {
        return _ARTHMAHAOracle.getPrice();
    }

    function getGlobalCR() public view override returns (uint256) {
        return _arthController.getGlobalCollateralRatio();
    }

    function getCollateralGMUBalance() external view override returns (uint256) {
        if (collateralPricePaused) {
            return
                (
                    _COLLATERAL.balanceOf(address(this)).sub(
                        unclaimedPoolCollateral
                    )
                )
                    .mul(10**_missingDeciamls)
                    .mul(pausedPrice)
                    .div(_PRICE_PRECISION);
        }

        uint256 ethGMUPrice = _arthController.getETHGMUPrice();
        uint256 ethCollateralPrice =
            _collateralETHOracle.consult(
                _wethAddress,
                _PRICE_PRECISION * (10**_missingDeciamls)
            );

        uint256 collateralGMUPrice =
            ethGMUPrice.mul(_PRICE_PRECISION).div(ethCollateralPrice);

        return
            (_COLLATERAL.balanceOf(address(this)).sub(unclaimedPoolCollateral))
                .mul(10**_missingDeciamls)
                .mul(collateralGMUPrice)
                .div(_PRICE_PRECISION);
    }

    // Returns the value of excess collateral held in this Arth pool, compared to what is
    // needed to maintain the global collateral ratio
    function getAvailableExcessCollateralDV()
        public
        view
        override
        returns (uint256)
    {
        uint256 totalSupply = _ARTH.totalSupply();
        uint256 globalCollateralRatio = getGlobalCR();
        uint256 globalCollatValue = _arthController.getGlobalCollateralValue();

        // Check if overcollateralized contract with CR > 1.
        if (globalCollateralRatio > _COLLATERAL_RATIO_PRECISION)
            globalCollateralRatio = _COLLATERAL_RATIO_PRECISION;

        // Calculates collateral needed to back each 1 ARTH with $1 of collateral at current CR.
        uint256 reqCollateralGMUValue =
            (totalSupply.mul(globalCollateralRatio)).div(
                _COLLATERAL_RATIO_PRECISION
            );

        // TODO: add a 10-20% buffer for volatile collaterals.
        if (globalCollatValue > reqCollateralGMUValue) {
            uint256 excessCollateral =
                globalCollatValue.sub(reqCollateralGMUValue);
            uint256 bufferValue =
                excessCollateral.mul(buybackCollateralBuffer).div(100);

            return excessCollateral.sub(bufferValue);
        }

        return 0;
    }

    function getTargetCollateralValue() public view returns (uint256) {
        return
            _ARTH
                .totalSupply()
                .mul(_arthController.getGlobalCollateralRatio())
                .div(1e6);
    }

    function getRecollateralizationDiscount() public view override returns (uint256) {
        uint256 targetCollatValue = getTargetCollateralValue();
        uint256 currentCollatValue = _arthController.getGlobalCollateralValue();

        uint256 percentCollateral = currentCollatValue.mul(100).div(targetCollatValue);

        return _recollateralizeDiscountCruve
            .getY(percentCollateral)
            .mul(_PRICE_PRECISION)
            .div(1e18);
    }

    function getCollateralPrice() public view override returns (uint256) {
        if (collateralPricePaused) return pausedPrice;

        uint256 ethGMUPrice = _arthController.getETHGMUPrice();

        return
            ethGMUPrice.mul(_PRICE_PRECISION).div(
                _collateralETHOracle.consult(
                    _wethAddress,
                    _PRICE_PRECISION * (10**_missingDeciamls)
                )
            );
    }

    function estimateStabilityFeeInMAHA(uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 stabilityFeeInARTH = amount.mul(stabilityFee).div(100);
        return getARTHMAHAPrice().mul(stabilityFeeInARTH).div(1e18); // NOTE: this is might change asper ARTH's decimals and price precision.
    }

    /**
     * Internal.
     */

    function _chargeStabilityFee(uint256 amount) internal {
        require(amount > 0, 'ArthPool: amount = 0');

        if (stabilityFee > 0) {
            uint256 stabilityFeeInMAHA = estimateStabilityFeeInMAHA(amount);
            _MAHA.burnFrom(msg.sender, stabilityFeeInMAHA);
            emit StabilityFeesCharged(msg.sender, stabilityFeeInMAHA);
        }

        return;
    }
}
