// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {IERC20} from '../ERC20/IERC20.sol';
import {SafeMath} from '../utils/math/SafeMath.sol';
import {IARTHPool} from './Pools/IARTHPool.sol';
import {IARTHController} from './IARTHController.sol';
import {AccessControl} from '../access/AccessControl.sol';
import {IChainlinkOracle} from '../Oracle/IChainlinkOracle.sol';
import {IUniswapPairOracle} from '../Oracle/IUniswapPairOracle.sol';

/**
 * @title  ARTHStablecoin.
 * @author MahaDAO.
 */
contract ArthController is AccessControl, IARTHController {
    using SafeMath for uint256;

    /**
     * Data structures.
     */

    enum PriceChoice {ARTH, ARTHX}

    /**
     * State variables.
     */

    IERC20 public ARTH;
    IERC20 public ARTHX;

    IChainlinkOracle private _ETHGMUPricer;
    IUniswapPairOracle private _ARTHETHOracle;
    IUniswapPairOracle private _ARTHXETHOracle;

    address public wethAddress;
    address public arthxAddress;
    address public ownerAddress;
    address public creatorAddress;
    address public timelockAddress;
    address public controllerAddress;
    address public arthETHOracleAddress;
    address public arthxETHOracleAddress;
    address public ethGMUConsumerAddress;
    address public DEFAULT_ADMIN_ADDRESS;

    uint256 public arthStep; // Amount to change the collateralization ratio by upon refresing CR.
    uint256 public mintingFee; // 6 decimals of precision, divide by 1000000 in calculations for fee.
    uint256 public redemptionFee;
    uint256 public refreshCooldown; // Seconds to wait before being refresh CR again.
    uint256 public globalCollateralRatio;

    // The bound above and below the price target at which the refershing CR
    // will not change the collateral ratio.
    uint256 public priceBand;

    // The price of ARTH at which the collateral ratio will respond to.
    // This value is only used for the collateral ratio mechanism & not for
    // minting and redeeming which are hardcoded at $1.
    uint256 public priceTarget;

    // There needs to be a time interval that this can be called.
    // Otherwise it can be called multiple times per expansion.
    // Last time the refreshCollateralRatio function was called.
    uint256 public lastCallTime;

    // This is to help with establishing the Uniswap pools, as they need liquidity.
    uint256 public constant genesisSupply = 2000000e18; // 2M ARTH (testnet) & 5k (Mainnet).

    bool public useGlobalCRForMint = true;
    bool public useGlobalCRForRedeem = true;
    bool public useGlobalCRForRecollateralize = true;

    uint256 public mintCollateralRatio;
    uint256 public redeemCollateralRatio;
    uint256 public recollateralizeCollateralRatio;

    bool public isColalteralRatioPaused = false;

    bytes32 public constant COLLATERAL_RATIO_PAUSER =
        keccak256('COLLATERAL_RATIO_PAUSER');

    address[] public arthPoolsArray; // These contracts are able to mint ARTH.

    mapping(address => bool) public override arthPools;

    uint8 private _ethGMUPricerDecimals;
    uint256 private constant _PRICE_PRECISION = 1e6;

    /**
     * Modifiers.
     */

    modifier onlyCollateralRatioPauser() {
        require(hasRole(COLLATERAL_RATIO_PAUSER, msg.sender));
        _;
    }

    modifier onlyPools() {
        require(arthPools[msg.sender] == true, 'ARTHController: FORBIDDEN');
        _;
    }

    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            'ARTHController: FORBIDDEN'
        );
        _;
    }

    modifier onlyByOwnerOrGovernance() {
        require(
            msg.sender == ownerAddress ||
                msg.sender == timelockAddress ||
                msg.sender == controllerAddress,
            'ARTHController: FORBIDDEN'
        );
        _;
    }

    modifier onlyByOwnerGovernanceOrPool() {
        require(
            msg.sender == ownerAddress ||
                msg.sender == timelockAddress ||
                arthPools[msg.sender] == true,
            'ARTHController: FORBIDDEN'
        );
        _;
    }

    /**
     * Constructor.
     */

    constructor(address _creatorAddress, address _timelockAddress) {
        creatorAddress = _creatorAddress;
        timelockAddress = _timelockAddress;

        ownerAddress = _creatorAddress;
        DEFAULT_ADMIN_ADDRESS = _msgSender();

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        grantRole(COLLATERAL_RATIO_PAUSER, creatorAddress);
        grantRole(COLLATERAL_RATIO_PAUSER, timelockAddress);

        arthStep = 2500; // 6 decimals of precision, equal to 0.25%.
        priceBand = 5000; // Collateral ratio will not adjust if between $0.995 and $1.005 at genesis.
        priceTarget = 1000000; // Collateral ratio will adjust according to the $1 price target at genesis.
        refreshCooldown = 3600; // Refresh cooldown period is set to 1 hour (3600 seconds) at genesis.
        globalCollateralRatio = 1000000; // Arth system starts off fully collateralized (6 decimals of precision).
    }

    /**
     * External.
     */

    function toggleUseGlobalCRForMint(bool flag)
        external
        override
        onlyByOwnerGovernanceOrPool
    {
        useGlobalCRForMint = flag;
    }

    function toggleUseGlobalCRForRedeem(bool flag)
        external
        override
        onlyByOwnerGovernanceOrPool
    {
        useGlobalCRForRedeem = flag;
    }

    function toggleUseGlobalCRForRecollateralize(bool flag)
        external
        override
        onlyByOwnerGovernanceOrPool
    {
        useGlobalCRForRecollateralize = flag;
    }

    function setMintCollateralRatio(uint256 val)
        external
        override
        onlyByOwnerGovernanceOrPool
    {
        mintCollateralRatio = val;
    }

    function setRedeemCollateralRatio(uint256 val)
        external
        override
        onlyByOwnerGovernanceOrPool
    {
        redeemCollateralRatio = val;
    }

    function setRecollateralizeCollateralRatio(uint256 val)
        external
        override
        onlyByOwnerGovernanceOrPool
    {
        recollateralizeCollateralRatio = val;
    }

    function refreshCollateralRatio() external override {
        require(
            isColalteralRatioPaused == false,
            'ARTHController: Collateral Ratio has been paused'
        );
        require(
            block.timestamp - lastCallTime >= refreshCooldown,
            'ARTHController: must wait till callable again'
        );

        uint256 currentPrice = getARTHPrice();

        // Check whether to increase or decrease the CR.
        if (currentPrice > priceTarget.add(priceBand)) {
            // Decrease the collateral ratio.
            if (globalCollateralRatio <= arthStep) {
                globalCollateralRatio = 0; // If within a step of 0, go to 0
            } else {
                globalCollateralRatio = globalCollateralRatio.sub(arthStep);
            }
        } else if (currentPrice < priceTarget.sub(priceBand)) {
            // Increase collateral ratio.
            if (globalCollateralRatio.add(arthStep) >= 1000000) {
                globalCollateralRatio = 1000000; // Cap collateral ratio at 1.000000.
            } else {
                globalCollateralRatio = globalCollateralRatio.add(arthStep);
            }
        }

        lastCallTime = block.timestamp; // Set the time of the last expansion
    }

    /// @notice Adds collateral addresses supported.
    /// @dev    Collateral must be an ERC20.
    function addPool(address poolAddress)
        external
        override
        onlyByOwnerOrGovernance
    {
        require(
            arthPools[poolAddress] == false,
            'ARTHController: address present'
        );

        arthPools[poolAddress] = true;
        arthPoolsArray.push(poolAddress);
    }

    function removePool(address poolAddress)
        external
        override
        onlyByOwnerOrGovernance
    {
        require(
            arthPools[poolAddress] == true,
            'ARTHController: address absent'
        );

        // Delete from the mapping.
        delete arthPools[poolAddress];

        // 'Delete' from the array by setting the address to 0x0
        for (uint256 i = 0; i < arthPoolsArray.length; i++) {
            if (arthPoolsArray[i] == poolAddress) {
                arthPoolsArray[i] = address(0); // This will leave a null in the array and keep the indices the same.
                break;
            }
        }
    }

    /**
     * Public.
     */

    function setGlobalCollateralRatio(uint256 _globalCollateralRatio)
        external
        override
        onlyAdmin
    {
        globalCollateralRatio = _globalCollateralRatio;
    }

    function setARTHXAddress(address _arthxAddress)
        external
        override
        onlyByOwnerOrGovernance
    {
        arthxAddress = _arthxAddress;
    }

    function setPriceTarget(uint256 newPriceTarget)
        external
        override
        onlyByOwnerOrGovernance
    {
        priceTarget = newPriceTarget;
    }

    function setRefreshCooldown(uint256 newCooldown)
        external
        override
        onlyByOwnerOrGovernance
    {
        refreshCooldown = newCooldown;
    }

    function setETHGMUOracle(address _ethGMUConsumerAddress)
        external
        override
        onlyByOwnerOrGovernance
    {
        ethGMUConsumerAddress = _ethGMUConsumerAddress;
        _ETHGMUPricer = IChainlinkOracle(ethGMUConsumerAddress);
        _ethGMUPricerDecimals = _ETHGMUPricer.getDecimals();
    }

    function setARTHXETHOracle(
        address _arthxOracleAddress,
        address _wethAddress
    ) external override onlyByOwnerOrGovernance {
        arthxETHOracleAddress = _arthxOracleAddress;
        _ARTHXETHOracle = IUniswapPairOracle(_arthxOracleAddress);
        wethAddress = _wethAddress;
    }

    function setARTHETHOracle(address _arthOracleAddress, address _wethAddress)
        external
        override
        onlyByOwnerOrGovernance
    {
        arthETHOracleAddress = _arthOracleAddress;
        _ARTHETHOracle = IUniswapPairOracle(_arthOracleAddress);
        wethAddress = _wethAddress;
    }

    function toggleCollateralRatio() external override onlyCollateralRatioPauser {
        isColalteralRatioPaused = !isColalteralRatioPaused;
    }

    function setMintingFee(uint256 fee)
        external
        override
        onlyByOwnerOrGovernance
    {
        mintingFee = fee;
    }

    function setArthStep(uint256 newStep)
        external
        override
        onlyByOwnerOrGovernance
    {
        arthStep = newStep;
    }

    function setRedemptionFee(uint256 fee)
        external
        override
        onlyByOwnerOrGovernance
    {
        redemptionFee = fee;
    }

    function setOwner(address _ownerAddress)
        external
        override
        onlyByOwnerOrGovernance
    {
        ownerAddress = _ownerAddress;
    }

    function setPriceBand(uint256 _priceBand)
        external
        override
        onlyByOwnerOrGovernance
    {
        priceBand = _priceBand;
    }

    function setTimelock(address newTimelock)
        external
        override
        onlyByOwnerOrGovernance
    {
        timelockAddress = newTimelock;
    }

    function getRefreshCooldown() external view override returns (uint256) {
        return refreshCooldown;
    }

    function getARTHPrice() public view override returns (uint256) {
        return _getOraclePrice(PriceChoice.ARTH);
    }

    function getARTHXPrice() public view override returns (uint256) {
        return _getOraclePrice(PriceChoice.ARTHX);
    }

    function getETHGMUPrice() public view override returns (uint256) {
        return
            uint256(_ETHGMUPricer.getLatestPrice()).mul(_PRICE_PRECISION).div(
                uint256(10)**_ethGMUPricerDecimals
            );
    }

    function getGlobalCollateralRatio() public view override returns (uint256) {
        return globalCollateralRatio;
    }

    function getGlobalCollateralValue() public view override returns (uint256) {
        uint256 totalCollateralValueD18 = 0;

        for (uint256 i = 0; i < arthPoolsArray.length; i++) {
            // Exclude null addresses.
            if (arthPoolsArray[i] != address(0)) {
                totalCollateralValueD18 = totalCollateralValueD18.add(
                    IARTHPool(arthPoolsArray[i]).getCollateralGMUBalance()
                );
            }
        }

        return totalCollateralValueD18;
    }

    function getCRForMint() external view override returns(uint256) {
        if (useGlobalCRForMint) return getGlobalCollateralRatio();

        return mintCollateralRatio;
    }

    function getCRForRedeem() external view override returns(uint256) {
        if (useGlobalCRForRedeem) return getGlobalCollateralRatio();

        return redeemCollateralRatio;
    }

    function getCRForRecollateralize() external view override returns(uint256) {
        if (useGlobalCRForRecollateralize) return getGlobalCollateralRatio();

        return recollateralizeCollateralRatio;
    }

    function getARTHInfo()
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            getARTHPrice(), // ARTH price.
            getARTHXPrice(), // ARTHX price.
            ARTH.totalSupply(), // ARTH total supply.
            globalCollateralRatio, // Global collateralization ratio.
            getGlobalCollateralValue(), // Global collateral value.
            mintingFee, // Minting fee.
            redemptionFee, // Redemtion fee.
            getETHGMUPrice() // ETH/GMU price.
        );
    }

    /**
     * Internal.
     */

    /// @param choice 'ARTH' or 'ARTHX'.
    function _getOraclePrice(PriceChoice choice)
        internal
        view
        returns (uint256)
    {
        uint256 eth2GMUPrice =
            uint256(_ETHGMUPricer.getLatestPrice()).mul(_PRICE_PRECISION).div(
                uint256(10)**_ethGMUPricerDecimals
            );

        uint256 priceVsETH;

        if (choice == PriceChoice.ARTH) {
            priceVsETH = uint256(
                _ARTHETHOracle.consult(wethAddress, _PRICE_PRECISION) // How much ARTH if you put in _PRICE_PRECISION WETH ?
            );
        } else if (choice == PriceChoice.ARTHX) {
            priceVsETH = uint256(
                _ARTHXETHOracle.consult(wethAddress, _PRICE_PRECISION) // How much ARTHX if you put in _PRICE_PRECISION WETH ?
            );
        } else
            revert(
                'INVALID PRICE CHOICE. Needs to be either 0 (ARTH) or 1 (ARTHX)'
            );

        return eth2GMUPrice.mul(_PRICE_PRECISION).div(priceVsETH);
    }
}
