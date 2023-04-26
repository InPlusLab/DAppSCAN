// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./lib/Babylonian.sol";
import "./owner/Operator.sol";
import "./utils/ContractGuard.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IBoardroom.sol";

contract Treasury is ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;


    uint256 public constant PERIOD = 8 hours;

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    // epoch
    uint256 public startTime;
    uint256 public epoch = 0;
    uint256 public epochSupplyContractionLeft = 0;

    // exclusions from total supply
    address[] public excludedFromTotalSupply = [
        address(0x28d81863438F25b6EC4c9DA28348445FC5E44196) // DarkRewardPool
    ];

    // core components
    address public dark;
    address public light;
    address public sky;

    address public boardroom;
    address public darkOracle;

    uint256 public boardroomWithdrawFee;
    uint256 public boardroomStakeFee;

    // price
    uint256 public darkPriceOne;
    uint256 public darkPriceCeiling;

    uint256 public seigniorageSaved;

    uint256 public darkSupplyTarget;

    uint256 public maxSupplyExpansionPercent;
    uint256 public bondDepletionFloorPercent;
    uint256 public seigniorageExpansionFloorPercent;
    uint256 public maxSupplyContractionPercent;
    uint256 public maxDebtRatioPercent;

    // 21 first epochs (1 week) with 3.5% expansion regardless of DARK price
    uint256 public bootstrapEpochs;
    uint256 public bootstrapSupplyExpansionPercent;

    /* =================== Added variables =================== */
    uint256 public previousEpochDarkPrice;
    uint256 public allocateSeigniorageSalary;
    uint256 public maxDiscountRate; // when purchasing bond
    uint256 public maxPremiumRate; // when redeeming bond
    uint256 public discountPercent;
    uint256 public premiumThreshold;
    uint256 public premiumPercent;
    uint256 public mintingFactorForPayingDebt; // print extra DARK during debt phase

    // 45% for Stakers in boardroom (THIS)
    // 45% for DAO fund
    // 2% for DEV fund
    // 8% for INSURANCE fund
    address public daoFund;
    uint256 public daoFundSharedPercent;

    address public devFund;
    uint256 public devFundSharedPercent;

    address public insuranceFund;
    uint256 public insuranceFundSharedPercent;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event BurnedBonds(address indexed from, uint256 bondAmount);
    event RedeemedBonds(address indexed from, uint256 darkAmount, uint256 bondAmount);
    event BoughtBonds(address indexed from, uint256 darkAmount, uint256 bondAmount);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event BoardroomFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFundFunded(uint256 timestamp, uint256 seigniorage);
    event DevFundFunded(uint256 timestamp, uint256 seigniorage);
    event InsuranceFundFunded(uint256 timestamp, uint256 seigniorage);
    event Seigniorage(uint256 epoch, uint256 twap, uint256 expansion);

    /* =================== Modifier =================== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Treasury: caller is not the operator");
        _;
    }

    modifier checkCondition {
        require(now >= startTime, "Treasury: not started yet");

        _;
    }

    modifier checkEpoch {
        require(now >= nextEpochPoint(), "Treasury: not opened yet");

        _;

        epoch = epoch.add(1);
        epochSupplyContractionLeft = (getDarkPrice() > darkPriceCeiling) ? 0 : getDarkCirculatingSupply().mul(maxSupplyContractionPercent).div(10000);
    }

    modifier checkOperator {
        require(
            IBasisAsset(dark).operator() == address(this) &&
                IBasisAsset(light).operator() == address(this) &&
                IBasisAsset(sky).operator() == address(this) &&
                Operator(boardroom).operator() == address(this),
            "Treasury: need more permission"
        );

        _;
    }

    modifier notInitialized {
        require(!initialized, "Treasury: already initialized");

        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function isInitialized() public view returns (bool) {
        return initialized;
    }

    // epoch
    function nextEpochPoint() public view returns (uint256) {
        return startTime.add(epoch.mul(PERIOD));
    }

    // oracle
    function getDarkPrice() public view returns (uint256 darkPrice) {
        try IOracle(darkOracle).consult(dark, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult DARK price from the oracle");
        }
    }

    function getDarkUpdatedPrice() public view returns (uint256 _darkPrice) {
        try IOracle(darkOracle).twap(dark, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult DARK price from the oracle");
        }
    }

    // budget
    function getReserve() public view returns (uint256) {
        return seigniorageSaved;
    }

    function getBurnableDarkLeft() public view returns (uint256 _burnableDarkLeft) {
        uint256 _darkPrice = getDarkPrice();
        if (_darkPrice <= darkPriceOne) {
            uint256 _darkSupply = getDarkCirculatingSupply();
            uint256 _bondMaxSupply = _darkSupply.mul(maxDebtRatioPercent).div(10000);
            uint256 _bondSupply = IERC20(light).totalSupply();
            if (_bondMaxSupply > _bondSupply) {
                uint256 _maxMintableBond = _bondMaxSupply.sub(_bondSupply);
                uint256 _maxBurnableDark = _maxMintableBond.mul(_darkPrice).div(1e18);
                _burnableDarkLeft = Math.min(epochSupplyContractionLeft, _maxBurnableDark);
            }
        }
    }

    function getRedeemableBonds() public view returns (uint256 _redeemableBonds) {
        uint256 _darkPrice = getDarkPrice();
        if (_darkPrice > darkPriceCeiling) {
            uint256 _totalDark = IERC20(dark).balanceOf(address(this));
            uint256 _rate = getBondPremiumRate();
            if (_rate > 0) {
                _redeemableBonds = _totalDark.mul(1e18).div(_rate);
            }
        }
    }

    function getBondDiscountRate() public view returns (uint256 _rate) {
        uint256 _darkPrice = getDarkPrice();
        if (_darkPrice <= darkPriceOne) {
            if (discountPercent == 0) {
                // no discount
                _rate = darkPriceOne;
            } else {
                uint256 _bondAmount = darkPriceOne.mul(1e18).div(_darkPrice); // to burn 1 DARK
                uint256 _discountAmount = _bondAmount.sub(darkPriceOne).mul(discountPercent).div(10000);
                _rate = darkPriceOne.add(_discountAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    function getBondPremiumRate() public view returns (uint256 _rate) {
        uint256 _darkPrice = getDarkPrice();
        if (_darkPrice > darkPriceCeiling) {
            uint256 _darkPricePremiumThreshold = darkPriceOne.mul(premiumThreshold).div(100);
            if (_darkPrice >= _darkPricePremiumThreshold) {
                //Price > 1.10
                uint256 _premiumAmount = _darkPrice.sub(darkPriceOne).mul(premiumPercent).div(10000);
                _rate = darkPriceOne.add(_premiumAmount);
                if (maxPremiumRate > 0 && _rate > maxPremiumRate) {
                    _rate = maxPremiumRate;
                }
            } else {
                // no premium bonus
                _rate = darkPriceOne;
            }
        }
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _dark,
        address _light,
        address _sky,
        address _darkOracle,
        address _boardroom,
        uint256 _startTime
    ) public notInitialized {
        dark = _dark;
        light = _light;
        sky = _sky;
        darkOracle = _darkOracle;
        boardroom = _boardroom;
        startTime = _startTime;

        darkPriceOne = 10**18;
        darkPriceCeiling = darkPriceOne.mul(101).div(100);

        darkSupplyTarget = 1000000 ether;

        maxSupplyExpansionPercent = 350; // Upto 3.5% supply for expansion

        boardroomWithdrawFee = 2; // 2% withdraw fee when under peg

        bondDepletionFloorPercent = 10000; // 100% of Bond supply for depletion floor
        seigniorageExpansionFloorPercent = 3500; // At least 35% of expansion reserved for boardroom
        maxSupplyContractionPercent = 300; // Upto 3.0% supply for contraction (to burn DARK and mint LIGHT)
        maxDebtRatioPercent = 3500; // Upto 35% supply of LIGHT to purchase

        premiumThreshold = 110;
        premiumPercent = 7000;

        allocateSeigniorageSalary = 0.2 ether;

        // First 21 epochs with 4.5% expansion
        bootstrapEpochs = 21;
        bootstrapSupplyExpansionPercent = 450;

        // set seigniorageSaved to it's balance
        seigniorageSaved = IERC20(dark).balanceOf(address(this));

        initialized = true;
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setBoardroom(address _boardroom) external onlyOperator {
        boardroom = _boardroom;
    }

    function setBoardroomWithdrawFee(uint256 _boardroomWithdrawFee) external onlyOperator {
        require(_boardroomWithdrawFee <= 20, "Max withdraw fee is 20%");
        boardroomWithdrawFee = _boardroomWithdrawFee;
    }

    function setBoardroomStakeFee(uint256 _boardroomStakeFee) external onlyOperator {
        require(_boardroomStakeFee <= 5, "Max stake fee is 5%");
        boardroomStakeFee = _boardroomStakeFee;
        IBoardroom(boardroom).setStakeFee(boardroomStakeFee);
    }

    function setDarkOracle(address _darkOracle) external onlyOperator {
        darkOracle = _darkOracle;
    }

    function setDarkPriceCeiling(uint256 _darkPriceCeiling) external onlyOperator {
        require(_darkPriceCeiling >= darkPriceOne && _darkPriceCeiling <= darkPriceOne.mul(120).div(100), "out of range"); // [$1.0, $1.2]
        darkPriceCeiling = _darkPriceCeiling;
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent) external onlyOperator {
        require(_maxSupplyExpansionPercent >= 10 && _maxSupplyExpansionPercent <= 1000, "_maxSupplyExpansionPercent: out of range"); // [0.1%, 10%]
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
    }

    function setBondDepletionFloorPercent(uint256 _bondDepletionFloorPercent) external onlyOperator {
        require(_bondDepletionFloorPercent >= 500 && _bondDepletionFloorPercent <= 10000, "out of range"); // [5%, 100%]
        bondDepletionFloorPercent = _bondDepletionFloorPercent;
    }

    function setMaxSupplyContractionPercent(uint256 _maxSupplyContractionPercent) external onlyOperator {
        require(_maxSupplyContractionPercent >= 100 && _maxSupplyContractionPercent <= 1500, "out of range"); // [0.1%, 15%]
        maxSupplyContractionPercent = _maxSupplyContractionPercent;
    }

    function setMaxDebtRatioPercent(uint256 _maxDebtRatioPercent) external onlyOperator {
        require(_maxDebtRatioPercent >= 1000 && _maxDebtRatioPercent <= 10000, "out of range"); // [10%, 100%]
        maxDebtRatioPercent = _maxDebtRatioPercent;
    }

    function setBootstrap(uint256 _bootstrapEpochs, uint256 _bootstrapSupplyExpansionPercent) external onlyOperator {
        require(_bootstrapEpochs <= 90, "_bootstrapEpochs: out of range"); // <= 1 month
        require(_bootstrapSupplyExpansionPercent >= 100 && _bootstrapSupplyExpansionPercent <= 1000, "_bootstrapSupplyExpansionPercent: out of range"); // [1%, 10%]
        bootstrapEpochs = _bootstrapEpochs;
        bootstrapSupplyExpansionPercent = _bootstrapSupplyExpansionPercent;
    }

    function setExtraFunds(
        address _daoFund,
        uint256 _daoFundSharedPercent,
        address _devFund,
        uint256 _devFundSharedPercent,
        address _insuranceFund,
        uint256 _insuranceFundSharedPercent
    ) external onlyOperator {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 5000, "out of range"); // <= 50%
        require(_devFund != address(0), "zero");
        require(_devFundSharedPercent <= 1000, "out of range"); // <= 10%
        require(_insuranceFund != address(0), "zero");
        require(_insuranceFundSharedPercent <= 1000, "out of range"); // <= 10%

        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;

        devFund = _devFund;
        devFundSharedPercent = _devFundSharedPercent;

        insuranceFund = _insuranceFund;
        insuranceFundSharedPercent = _insuranceFundSharedPercent;
    }

    function setAllocateSeigniorageSalary(uint256 _allocateSeigniorageSalary) external onlyOperator {
        require(_allocateSeigniorageSalary <= 10 ether, "Treasury: dont pay too much");
        allocateSeigniorageSalary = _allocateSeigniorageSalary;
    }

    function setMaxDiscountRate(uint256 _maxDiscountRate) external onlyOperator {
        maxDiscountRate = _maxDiscountRate;
    }

    function setMaxPremiumRate(uint256 _maxPremiumRate) external onlyOperator {
        maxPremiumRate = _maxPremiumRate;
    }

    function setDiscountPercent(uint256 _discountPercent) external onlyOperator {
        require(_discountPercent <= 20000, "_discountPercent is over 200%");
        discountPercent = _discountPercent;
    }

    function setPremiumThreshold(uint256 _premiumThreshold) external onlyOperator {
        require(_premiumThreshold >= darkPriceCeiling, "_premiumThreshold exceeds darkPriceCeiling");
        require(_premiumThreshold <= 150, "_premiumThreshold is higher than 1.5");
        premiumThreshold = _premiumThreshold;
    }

    function setPremiumPercent(uint256 _premiumPercent) external onlyOperator {
        require(_premiumPercent <= 20000, "_premiumPercent is over 200%");
        premiumPercent = _premiumPercent;
    }

    function setMintingFactorForPayingDebt(uint256 _mintingFactorForPayingDebt) external onlyOperator {
        require(_mintingFactorForPayingDebt >= 10000 && _mintingFactorForPayingDebt <= 20000, "_mintingFactorForPayingDebt: out of range"); // [100%, 200%]
        mintingFactorForPayingDebt = _mintingFactorForPayingDebt;
    }

    function setDarkSupplyTarget(uint256 _darkSupplyTarget) external onlyOperator {
        require(_darkSupplyTarget > getDarkCirculatingSupply(), "too small"); // >= current circulating supply
        darkSupplyTarget = _darkSupplyTarget;
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function _updateDarkPrice() internal {
        try IOracle(darkOracle).update() {} catch {}
    }

    function getDarkCirculatingSupply() public view returns (uint256) {
        IERC20 darkErc20 = IERC20(dark);
        uint256 totalSupply = darkErc20.totalSupply();
        uint256 balanceExcluded = 0;
        for (uint8 entryId = 0; entryId < excludedFromTotalSupply.length; ++entryId) {
            balanceExcluded = balanceExcluded.add(darkErc20.balanceOf(excludedFromTotalSupply[entryId]));
        }
        return totalSupply.sub(balanceExcluded);
    }

    function buyBonds(uint256 _darkAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_darkAmount > 0, "Treasury: cannot purchase bonds with zero amount");

        uint256 darkPrice = getDarkPrice();
        require(darkPrice == targetPrice, "Treasury: DARK price moved");
        require(
            darkPrice < darkPriceOne, // price < $1
            "Treasury: darkPrice not eligible for bond purchase"
        );

        require(_darkAmount <= epochSupplyContractionLeft, "Treasury: not enough bond left to purchase");

        uint256 _rate = getBondDiscountRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _bondAmount = _darkAmount.mul(_rate).div(1e18);
        uint256 darkSupply = getDarkCirculatingSupply();
        uint256 newBondSupply = IERC20(light).totalSupply().add(_bondAmount);
        require(newBondSupply <= darkSupply.mul(maxDebtRatioPercent).div(10000), "over max debt ratio");

        IBasisAsset(dark).burnFrom(msg.sender, _darkAmount);
        IBasisAsset(light).mint(msg.sender, _bondAmount);

        epochSupplyContractionLeft = epochSupplyContractionLeft.sub(_darkAmount);
        _updateDarkPrice();

        emit BoughtBonds(msg.sender, _darkAmount, _bondAmount);
    }

    function redeemBonds(uint256 _bondAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_bondAmount > 0, "Treasury: cannot redeem bonds with zero amount");

        uint256 darkPrice = getDarkPrice();
        require(darkPrice == targetPrice, "Treasury: DARK price moved");
        require(
            darkPrice > darkPriceCeiling, // price > $1.01
            "Treasury: darkPrice not eligible for bond purchase"
        );

        uint256 _rate = getBondPremiumRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _darkAmount = _bondAmount.mul(_rate).div(1e18);
        require(IERC20(dark).balanceOf(address(this)) >= _darkAmount, "Treasury: treasury has no more budget");

        seigniorageSaved = seigniorageSaved.sub(Math.min(seigniorageSaved, _darkAmount));

        IBasisAsset(light).burnFrom(msg.sender, _bondAmount);
        IERC20(dark).safeTransfer(msg.sender, _darkAmount);

        _updateDarkPrice();

        emit RedeemedBonds(msg.sender, _darkAmount, _bondAmount);
    }

    function _sendToBoardroom(uint256 _amount) internal {
        IBasisAsset(dark).mint(address(this), _amount);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20(dark).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(now, _daoFundSharedAmount);
        }

        uint256 _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = _amount.mul(devFundSharedPercent).div(10000);
            IERC20(dark).transfer(devFund, _devFundSharedAmount);
            emit DevFundFunded(now, _devFundSharedAmount);
        }

        uint256 _insuranceFundSharedAmount = 0;
        if (insuranceFundSharedPercent > 0) {
            _insuranceFundSharedAmount = _amount.mul(insuranceFundSharedPercent).div(10000);
            IERC20(dark).transfer(insuranceFund, _insuranceFundSharedAmount);
            emit InsuranceFundFunded(now, _insuranceFundSharedAmount);
        }

        _amount = _amount.sub(_daoFundSharedAmount).sub(_devFundSharedAmount).sub(_insuranceFundSharedAmount);

        IERC20(dark).safeApprove(boardroom, 0);
        IERC20(dark).safeApprove(boardroom, _amount);
        IBoardroom(boardroom).allocateSeigniorage(_amount);
        emit BoardroomFunded(now, _amount);
    }

    function _calculateMaxSupplyExpansionPercent(uint256 _darkSupply) internal returns (uint256) {
        if (_darkSupply >= darkSupplyTarget) {
            darkSupplyTarget = darkSupplyTarget.mul(12500).div(10000); // +25%
            maxSupplyExpansionPercent = maxSupplyExpansionPercent.mul(9500).div(10000); // -5%
            if (maxSupplyExpansionPercent < 10) {
                maxSupplyExpansionPercent = 10; // min 0.1%
            }
        }
        return maxSupplyExpansionPercent;
    }

    function getDarkExpansionRate() public view returns (uint256 _rate) {
        if (epoch < bootstrapEpochs) { // 21 first epochs with 3.5% expansion
            _rate = bootstrapSupplyExpansionPercent;
        } else {
            uint256 _twap = getDarkPrice();
            if (_twap >= darkPriceCeiling) {
                uint256 _percentage = _twap.sub(darkPriceOne); // 1% = 1e16
                uint256 _mse = maxSupplyExpansionPercent.mul(1e14);
                if (_percentage > _mse) {
                    _percentage = _mse;
                }
                _rate = _percentage.div(1e14);
            }
        }
    }

    function getDarkExpansionAmount() external view returns (uint256) {
        uint256 darkSupply = getDarkCirculatingSupply().sub(seigniorageSaved);
        uint256 bondSupply = IERC20(light).totalSupply();
        uint256 _rate = getDarkExpansionRate();
        if (seigniorageSaved >= bondSupply.mul(bondDepletionFloorPercent).div(10000)) {
            // saved enough to pay debt, mint as usual rate
            return darkSupply.mul(_rate).div(10000);
        } else {
            // have not saved enough to pay debt, mint more
            uint256 _seigniorage = darkSupply.mul(_rate).div(10000);
            return _seigniorage.mul(seigniorageExpansionFloorPercent).div(10000);
        }
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        _updateDarkPrice();
        previousEpochDarkPrice = getDarkPrice();
        uint256 darkSupply = getDarkCirculatingSupply().sub(seigniorageSaved);
        if (epoch < bootstrapEpochs) {
            // 21 first epochs with 3.5% expansion
            _sendToBoardroom(darkSupply.mul(bootstrapSupplyExpansionPercent).div(10000));
            emit Seigniorage(epoch, previousEpochDarkPrice, darkSupply.mul(bootstrapSupplyExpansionPercent).div(10000));
        } else {
            if (previousEpochDarkPrice >= darkPriceCeiling) {
                IBoardroom(boardroom).setWithdrawFee(0);
                // Expansion ($DARK Price > 1 $CRO): there is some seigniorage to be allocated
                uint256 bondSupply = IERC20(light).totalSupply();
                uint256 _percentage = previousEpochDarkPrice.sub(darkPriceOne);
                uint256 _savedForBond;
                uint256 _savedForBoardroom;
                uint256 _mse = _calculateMaxSupplyExpansionPercent(darkSupply).mul(1e14);
                if (_percentage > _mse) {
                    _percentage = _mse;
                }
                if (seigniorageSaved >= bondSupply.mul(bondDepletionFloorPercent).div(10000)) {
                    // saved enough to pay debt, mint as usual rate
                    _savedForBoardroom = darkSupply.mul(_percentage).div(1e18);
                } else {
                    // have not saved enough to pay debt, mint more
                    uint256 _seigniorage = darkSupply.mul(_percentage).div(1e18);
                    _savedForBoardroom = _seigniorage.mul(seigniorageExpansionFloorPercent).div(10000);
                    _savedForBond = _seigniorage.sub(_savedForBoardroom);
                    if (mintingFactorForPayingDebt > 0) {
                        _savedForBond = _savedForBond.mul(mintingFactorForPayingDebt).div(10000);
                    }
                }
                if (_savedForBoardroom > 0) {
                    _sendToBoardroom(_savedForBoardroom);
                }
                if (_savedForBond > 0) {
                    seigniorageSaved = seigniorageSaved.add(_savedForBond);
                    IBasisAsset(dark).mint(address(this), _savedForBond);
                    emit TreasuryFunded(now, _savedForBond);
                }
                emit Seigniorage(epoch, previousEpochDarkPrice, _savedForBoardroom);
            } else {
                IBoardroom(boardroom).setWithdrawFee(boardroomWithdrawFee);
                emit Seigniorage(epoch, previousEpochDarkPrice, 0);
            }
        }
        if (allocateSeigniorageSalary > 0) {
            IBasisAsset(dark).mint(address(msg.sender), allocateSeigniorageSalary);
        }
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(dark), "dark");
        require(address(_token) != address(light), "light");
        require(address(_token) != address(sky), "share");
        _token.safeTransfer(_to, _amount);
    }

    function boardroomSetOperator(address _operator) external onlyOperator {
        IBoardroom(boardroom).setOperator(_operator);
    }

    function boardroomSetReserveFund(address _reserveFund) external onlyOperator {
        IBoardroom(boardroom).setReserveFund(_reserveFund);
    }

    function boardroomSetLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        IBoardroom(boardroom).setLockUp(_withdrawLockupEpochs, _rewardLockupEpochs);
    }

    function boardroomAllocateSeigniorage(uint256 amount) external onlyOperator {
        IBoardroom(boardroom).allocateSeigniorage(amount);
    }

    function boardroomGovernanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IBoardroom(boardroom).governanceRecoverUnsupported(_token, _amount, _to);
    }
}
