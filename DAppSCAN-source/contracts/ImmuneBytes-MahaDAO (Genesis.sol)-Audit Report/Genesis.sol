// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IARTHController} from '../Arth/IARTHController.sol';
import {IARTHX} from '../ARTHX/IARTHX.sol';
import {IARTHPool} from '../Arth/Pools/IARTHPool.sol';
import {IARTH} from '../Arth/IARTH.sol';
import {AccessControl} from '../access/AccessControl.sol';
import {SafeMath} from '../utils/math/SafeMath.sol';
import {IOracle} from '../Oracle/IOracle.sol';
import {ArthPoolLibrary} from '../Arth/Pools/ArthPoolLibrary.sol';
import {IERC20} from '../ERC20/IERC20.sol';
import {ILotteryRaffle} from './ILotteryRaffle.sol';

contract Genesis {
    using SafeMath for uint256;

    IARTHController public _arthController;
    IARTHX public _ARTHX;
    IARTH public _ARTH;
    IARTHPool public _arthpool;
    IERC20 public _COLLATERAL;
    IOracle public _collateralGMUOracle;
    ILotteryRaffle public lottery;
    uint256 private constant _PRICE_PRECISION = 1e6;
    uint256 public immutable _missingDeciamls;
    address public _ownerAddress;
    address public _timelockAddress;
    address public collateralGMUOracleAddress;

    event RedeemAlgorithmicARTH(uint256 arthAmount, uint256 arthxOutMin);

    modifier onlyByOwnerOrGovernance() {
        require(
            msg.sender == _timelockAddress || msg.sender == _ownerAddress,
            'ArthPool: You are not the owner or the governance timelock'
        );
        _;
    }

    constructor(
        address __arthContractAddress,
        address __arthxContractAddress,
        address __arthController,
        address __collateralAddress,
        address __creatorAddress,
        address __timelockAddress,
        address __arthPool
    ) {
        _arthController = IARTHController(__arthController);
        _ARTHX = IARTHX(__arthxContractAddress);
        _ARTH = IARTH(__arthContractAddress);
        _COLLATERAL = IERC20(__collateralAddress);
        _arthpool = IARTHPool(__arthPool);

        _missingDeciamls = uint256(18).sub(_COLLATERAL.decimals());
        _ownerAddress = __creatorAddress;
        _timelockAddress = __timelockAddress;
    }

    function setOwner(address _owner) public onlyByOwnerOrGovernance {
        _ownerAddress = _owner;
    }

    function usersLotteriesCount(address _address)
        public
        view
        returns (uint256)
    {
        return lottery.usersLottery(_address);
    }

    function lotteryAllocated() public view returns (uint256) {
        return lottery.getTokenCounts();
    }

    function lotteryOwner(uint256 _tokenID) public view returns (address) {
        address owner = lottery.tokenIdOwner(_tokenID);
        return owner;
    }

    function setLotteryContract(address _lotterContract)
        public
        onlyByOwnerOrGovernance
    {
        lottery = ILotteryRaffle(_lotterContract);
    }

    function setCollatGMUOracle(address _collateralGMUOracleAddress)
        external
        onlyByOwnerOrGovernance
    {
        collateralGMUOracleAddress = _collateralGMUOracleAddress;
        _collateralGMUOracle = IOracle(_collateralGMUOracleAddress);
    }

    function recollateralizeARTH(uint256 collateralAmount, uint256 arthxOutMin)
        external
        returns (uint256)
    {
        require(
            _arthController.getIsGenesisActive(),
            'Genesis: Genessis is inactive'
        );

        uint256 arthxPrice = _arthController.getARTHXPrice();

        (uint256 collateralUnits, uint256 amountToRecollateralize, ) =
            estimateAmountToRecollateralize(collateralAmount);

        uint256 collateralUnitsPrecision =
            collateralUnits.div(10**_missingDeciamls);

        // NEED to make sure that recollatFee is less than 1e6.
        uint256 arthxPaidBack =
            amountToRecollateralize
                .mul(_arthController.getRecollateralizationDiscount().add(1e6))
                .div(arthxPrice);

        require(
            arthxOutMin <= arthxPaidBack,
            'Genesis: Slippage limit reached'
        );
        require(
            _COLLATERAL.balanceOf(msg.sender) >= collateralUnitsPrecision,
            'Genesis: balance < required'
        );
        require(
            _COLLATERAL.transferFrom(
                msg.sender,
                address(_arthpool), //address(this),
                collateralUnitsPrecision
            ),
            'Genesis: transfer from failed'
        );

        uint256 lottriesCount = getLotteryAmount(collateralAmount);

        if (lottriesCount > 0) {
            lottery.rewardLottery(msg.sender, lottriesCount);
        }

        _ARTHX.poolMint(msg.sender, arthxPaidBack);

        return arthxPaidBack;
    }

    function getLotteryAmount(uint256 _collateralAmount)
        internal
        view
        returns (uint256)
    {
        uint256 collateralValue =
            _arthpool.getCollateralPrice().mul(_collateralAmount).div(10**6);
        uint256 lotteryAmount = 0;
        if (collateralValue >= 1000 * 10**_COLLATERAL.decimals()) {
            lotteryAmount = collateralValue.div(
                1000 * 10**_COLLATERAL.decimals()
            );
        }

        return lotteryAmount;
    }

    // Redeem ARTH for ARTHX. 0% collateral-backed
    function redeemAlgorithmicARTH(uint256 arthAmount, uint256 arthxOutMin)
        external
    {
        require(
            _arthController.getIsGenesisActive(),
            'Genesis 36: Genessis inactive'
        );
        require(
            _ARTH.balanceOf(msg.sender) >= arthAmount,
            'Genesis 37: Insufficient arth amount'
        );

        uint256 arthxPrice = _arthController.getARTHXPrice();
        uint256 arthxAmount = arthAmount.mul(_PRICE_PRECISION).div(arthxPrice);

        require(arthxOutMin <= arthxAmount, 'Slippage limit reached');

        _ARTH.poolBurnFrom(msg.sender, arthAmount);
        _ARTHX.poolMint(msg.sender, arthxAmount);

        emit RedeemAlgorithmicARTH(arthAmount, arthxAmount);
    }

    function estimateAmountToRecollateralize(uint256 collateralAmount)
        public
        view
        returns (
            uint256 collateralUnits,
            uint256 amountToRecollateralize,
            uint256 recollateralizePossible
        )
    {
        uint256 collateralAmountD18 = collateralAmount * (10**_missingDeciamls);
        uint256 arthTotalSupply = _arthController.getARTHSupply();
        uint256 collateralRatioForRecollateralize =
            _arthController.getGlobalCollateralRatio();
        uint256 globalCollatValue = _arthController.getGlobalCollateralValue();

        return
            ArthPoolLibrary.calcRecollateralizeARTHInner(
                collateralAmountD18,
                getCollateralPrice(),
                globalCollatValue,
                arthTotalSupply,
                collateralRatioForRecollateralize
            );
    }

    function getCollateralGMUBalance() external pure returns (uint256) {
        return 0;
    }

    function getCollateralPrice() public view returns (uint256) {
        return _collateralGMUOracle.getPrice();
    }
}
