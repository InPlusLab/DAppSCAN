// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../Dependencies/AstridMath.sol";
import "../Dependencies/BaseMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/SafeMath.sol";
import "../Interfaces/IActivePool.sol";
import "../Interfaces/IDefaultPool.sol";
import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/IAstridBase.sol";

/* 
* Base contract for VaultManager, BorrowerOperations and StabilityPool. Contains global system constants and
* common functions. 
* NOTE: this is the v0 version, where all parameters are fixed and non-adjustable. In v1, we will enable updates
* to the parameters (which potentially requires us to address contract size issues).
*/
contract AstridFixedBase is BaseMath, IAstridBase {
    using SafeMath for uint;

    uint constant public _100pct = 1000000000000000000; // 1e18 == 100%

    // Minimum collateral ratio for individual vaults.
    uint constant public MCR = 1300000000000000000; // 130%

    // Critical system collateral ratio. If the system's total collateral ratio (TCR) falls below the CCR, Recovery Mode is triggered.
    uint constant public CCR = 1500000000000000000; // 150%

    // Amount of BAI to be locked in gas pool on opening vaults
    uint constant public BAI_GAS_COMPENSATION = 10e18;

    // Minimum amount of net BAI debt a vault must have
    uint constant public MIN_NET_DEBT = 100e18;

    uint constant public PERCENT_DIVISOR = 200; // dividing by 200 yields 0.5%

    uint constant public BORROWING_FEE_FLOOR = DECIMAL_PRECISION / 1000 * 5; // 0.5%

    IActivePool public activePool;

    IDefaultPool public defaultPool;

    IPriceFeed public override priceFeed;

    // --- Gas compensation functions ---

    // Returns the composite debt (drawn debt + gas compensation) of a vault, for the purpose of ICR calculation
    function _getCompositeDebt(uint _debt) internal pure returns (uint) {
        return _debt.add(BAI_GAS_COMPENSATION);
    }

    function _getNetDebt(uint _debt) internal pure returns (uint) {
        return _debt.sub(BAI_GAS_COMPENSATION);
    }

    // Return the amount to be drawn from a vault's collateral and sent as gas compensation.
    function _getCollGasCompensation(uint _entireColl) internal pure returns (uint) {
        return _entireColl / PERCENT_DIVISOR;
    }

    function getEntireSystemColl() public view returns (uint entireSystemColl) {
        uint activeColl = activePool.getCOL();
        uint liquidatedColl = defaultPool.getCOL();

        return activeColl.add(liquidatedColl);
    }

    function getEntireSystemDebt() public view returns (uint entireSystemDebt) {
        uint activeDebt = activePool.getBAIDebt();
        uint closedDebt = defaultPool.getBAIDebt();

        return activeDebt.add(closedDebt);
    }

    function _getTCR(uint _price) internal view returns (uint TCR) {
        uint entireSystemColl = getEntireSystemColl();
        uint entireSystemDebt = getEntireSystemDebt();

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
}
