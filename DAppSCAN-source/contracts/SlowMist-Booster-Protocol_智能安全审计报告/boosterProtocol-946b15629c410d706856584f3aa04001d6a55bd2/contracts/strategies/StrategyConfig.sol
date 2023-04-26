// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import '../interfaces/IStrategyLink.sol';
import '../interfaces/IStrategyConfig.sol';
import '../interfaces/ISafeBox.sol';

// fund fee processing
// some functions of strategy
contract StrategyConfig is Ownable, IStrategyConfig {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public feeGather;           // fee gather
    address public reservedGather;      // reserved gather

    mapping (address => mapping(uint256=>uint256) ) public borrowFactor;
    mapping (address => mapping(uint256=>uint256) ) public liquidationFactor;
    mapping (address => mapping(uint256=>uint256) ) public farmPoolFactor;

    mapping (address => mapping(uint256=>uint256) ) public depositFee;  // deposit platform fee
    mapping (address => mapping(uint256=>uint256) ) public refundFee;   // reinvestment platform fee
    mapping (address => mapping(uint256=>uint256) ) public withdrawFee; // withdraw rewards platform fee
    mapping (address => mapping(uint256=>uint256) ) public claimFee;    // claim fee - no used
    mapping (address => mapping(uint256=>uint256) ) public liquidationFee;  // the hunter fee

    constructor() public {
        feeGather = msg.sender;
        reservedGather = msg.sender;
    }

    function setFeeGather(address _feeGather) external onlyOwner {
        feeGather = _feeGather;
    }

    function setReservedGather(address _reservedGather) external onlyOwner {
        reservedGather = _reservedGather;
    }

    // Lending burst
    function getBorrowFactor(address _strategy, uint256 _poolid) public override view returns (uint256 value) {
        value = borrowFactor[_strategy][_poolid];
    }

    function checkBorrowAndLiquidation(address _strategy, uint256 _poolid) internal returns (bool bok) {
        uint256 v = getBorrowFactor(_strategy, _poolid);
        if(v <= 0) {
            return true;
        }
        // MaxBorrowAmount = DepositAmount * BorrowFactor
        // MaxBorrowAmount / (DepositAmount + MaxBorrowAmount) * 100.5% < LiquidationFactor
        bok = v.mul(1005e6).div(v.add(1e9)) < getLiquidationFactor(_strategy, _poolid);
    }

    function setBorrowFactor(address _strategy, uint256 _poolid, uint256 _borrowFactor) external override onlyOwner {
        borrowFactor[_strategy][_poolid] = _borrowFactor;
        require(checkBorrowAndLiquidation(_strategy, _poolid), 'set error');
    }

    function getLiquidationFactor(address _strategy, uint256 _poolid) public override view returns (uint256 value) {
        value = liquidationFactor[_strategy][_poolid];
        if(value <= 0) {
            value = 8e8;  // 80% for default , 100% will be liquidation
        }
    }

    function setLiquidationFactor(address _strategy, uint256 _poolid, uint256 _liquidationFactor) external override onlyOwner {
        require(_liquidationFactor >= 2e8, 'too lower');
        liquidationFactor[_strategy][_poolid] = _liquidationFactor;
        require(checkBorrowAndLiquidation(_strategy, _poolid), 'set error');
    }

    function getFarmPoolFactor(address _strategy, uint256 _poolid) external override view returns (uint256 value) {
        value = farmPoolFactor[_strategy][_poolid];
        // == 0 no limit and > 0 limit by lptoken amount
    }

    function setFarmPoolFactor(address _strategy, uint256 _poolid, uint256 _farmPoolFactor) external override onlyOwner {
        farmPoolFactor[_strategy][_poolid] = _farmPoolFactor;
    }

    // fee config
    function getDepositFee(address _strategy, uint256 _poolid) external override view returns (address a, uint256 b) {
        a = feeGather;
        b = depositFee[_strategy][_poolid];
    }

    function setDepositFee(address _strategy, uint256 _poolid, uint256 _depositFee) external override onlyOwner {
        depositFee[_strategy][_poolid] = _depositFee;
    }

    function getWithdrawFee(address _strategy, uint256 _poolid) external override view returns (address a, uint256 b) {
        a = feeGather;
        b = withdrawFee[_strategy][_poolid];
    }

    function setWithdrawFee(address _strategy, uint256 _poolid, uint256 _withdrawFee) external override onlyOwner {
        withdrawFee[_strategy][_poolid] = _withdrawFee;
    }

    function getRefundFee(address _strategy, uint256 _poolid) external override view returns (address a, uint256 b) {
        a = feeGather;
        b = refundFee[_strategy][_poolid];
    }

    function setRefundFee(address _strategy, uint256 _poolid, uint256 _refundFee) external override onlyOwner {
        refundFee[_strategy][_poolid] = _refundFee;
    }

    function getClaimFee(address _strategy, uint256 _poolid) external override view returns (address a, uint256 b) {
        a = feeGather;
        b = claimFee[_strategy][_poolid];
    }

    function setClaimFee(address _strategy, uint256 _poolid, uint256 _claimFee) external override onlyOwner {
        claimFee[_strategy][_poolid] = _claimFee;
    }

    function getLiquidationFee(address _strategy, uint256 _poolid) external override view returns (address a, uint256 b) {
        a = reservedGather;
        b = liquidationFee[_strategy][_poolid];
    }

    function setLiquidationFee(address _strategy, uint256 _poolid, uint256 _liquidationFee) external override onlyOwner {
        liquidationFee[_strategy][_poolid] = _liquidationFee;
    }
}
