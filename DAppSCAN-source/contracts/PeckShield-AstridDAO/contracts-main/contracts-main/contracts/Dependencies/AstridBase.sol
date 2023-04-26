// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./AstridMath.sol";
import "./BaseMath.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./CheckContract.sol";
import "../Interfaces/IActivePool.sol";
import "../Interfaces/IDefaultPool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/IAstridBase.sol";

/* 
* Base contract for VaultManager, BorrowerOperations and StabilityPool. Contains global system constants and
* common functions. 
* NOTE: since we want to allow the base to be adjustable, we will have all contracts referencing it to store its
* address instead of inheriting it.
*/
contract AstridBase is BaseMath, IAstridBase, Ownable, CheckContract {
    using SafeMath for uint;

    uint constant public _100pct = 1000000000000000000; // 1e18 == 100%

    // Minimum collateral ratio for individual vaults. This is NOT a constant.
    uint public MCR = 1100000000000000000; // 110%

    // Critical system collateral ratio. If the system's total collateral ratio (TCR) falls below the CCR, Recovery Mode is triggered.
    // This is NOT a constant.
    uint public CCR = 1500000000000000000; // 150%

    // Amount of BAI to be locked in gas pool on opening vaults
    uint public BAI_GAS_COMPENSATION = 200e18;

    // Minimum amount of net BAI debt a vault must have
    uint public MIN_NET_DEBT = 1800e18;

    uint public PERCENT_DIVISOR = 200; // dividing by 200 yields 0.5%

    uint public BORROWING_FEE_FLOOR = DECIMAL_PRECISION / 1000 * 5; // 0.5%

    IActivePool public activePool;

    IDefaultPool public defaultPool;

    IPriceFeed public override priceFeed;

    // --- Gas compensation functions ---

    // Returns the composite debt (drawn debt + gas compensation) of a vault, for the purpose of ICR calculation
    function _getCompositeDebt(uint _debt) internal view returns (uint) {
        return _debt.add(BAI_GAS_COMPENSATION);
    }

    function _getNetDebt(uint _debt) internal view returns (uint) {
        return _debt.sub(BAI_GAS_COMPENSATION);
    }

    // Return the amount to be drawn from a vault's collateral and sent as gas compensation.
    function _getCollGasCompensation(uint _entireColl) internal view returns (uint) {
        return _entireColl / PERCENT_DIVISOR;
    }

    function _getEntireSystemColl() internal view returns (uint entireSystemColl) {
        uint activeColl = activePool.getCOL();
        uint liquidatedColl = defaultPool.getCOL();

        return activeColl.add(liquidatedColl);
    }

    function _getEntireSystemDebt() internal view returns (uint entireSystemDebt) {
        uint activeDebt = activePool.getBAIDebt();
        uint closedDebt = defaultPool.getBAIDebt();

        return activeDebt.add(closedDebt);
    }

    function _getTCR(uint _price) internal view returns (uint TCR) {
        uint entireSystemColl = _getEntireSystemColl();
        uint entireSystemDebt = _getEntireSystemDebt();

        TCR = AstridMath._computeCR(entireSystemColl, entireSystemDebt, _price);

        return TCR;
    }

    function _checkRecoveryMode(uint _price) internal view returns (bool) {
        uint TCR = _getTCR(_price);

        return TCR < CCR;
    }

    function _requireUserAcceptsFee(uint _fee, uint _amount, uint _maxFeePercentage) internal pure {
        uint feePercentage = _fee.mul(DECIMAL_PRECISION).div(_amount);
        require(feePercentage <= _maxFeePercentage, "Fee exceeded provided maximum");
    }

    // --- System parameters modification functions ---
    // All below calls require owner.
    function setAddresses(
        address _activePool,
        address _defaultPool,
        address _priceFeed
    ) public onlyOwner {
        checkContract(_activePool);
        checkContract(_defaultPool);
        checkContract(_priceFeed);
        activePool = IActivePool(_activePool);
        defaultPool = IDefaultPool(_defaultPool);
        priceFeed = IPriceFeed(_priceFeed);
    }

    function setParams(
        uint _MCR,
        uint _CCR,
        uint _BAIGasCompensation,
        uint _minNetDebt,
        uint _percentageDivisor,
        uint _borrowingFeeFloor
    ) public onlyOwner {
        require(_MCR > _100pct, "MCR cannot < 100%");
        require(_CCR > _100pct, "CCR cannot < 100%");
        require(_BAIGasCompensation > 0, "Gas compensation must > 0");
        require(_minNetDebt > 0, "Min net debt must > 0");
        require(_percentageDivisor > 0, "Percentage divisor must > 0");
        // Borrowing fee floor can be 0 if necessary.

        MCR = _MCR;
        CCR = _CCR;
        BAI_GAS_COMPENSATION = _BAIGasCompensation;
        MIN_NET_DEBT = _minNetDebt;
        PERCENT_DIVISOR = _percentageDivisor;
        BORROWING_FEE_FLOOR = _borrowingFeeFloor;
    }
}
