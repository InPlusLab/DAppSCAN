//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IPandoAssembly.sol";

contract PandoPool is Ownable, Pausable {

    using SafeERC20 for IERC20;
    address public pandoAssembly;
    mapping(address => bool) operators;
    uint256 public allocationDailyPercent;
    uint256 constant PRECISION = 1000;
    address public usdt;

    constructor (address _usdt, address _pandoAssembly, uint256 _allocationDailyPercent) {
        usdt = _usdt;
        pandoAssembly = _pandoAssembly;
        allocationDailyPercent = _allocationDailyPercent;
    }

    modifier onlyOperator() {
        // Try to make flash-loan exploit harder to do by only allowing externally owned addresses.
        require(operators[msg.sender] == true, "PandoPool: must be operator");
        _;
    }

    function allocateReward(uint256 _days) external onlyOperator whenNotPaused{
        uint256 _balance = IERC20(usdt).balanceOf(address(this));
        uint256 _allocationAmount = _balance * allocationDailyPercent / PRECISION;

        IERC20(usdt).safeApprove(pandoAssembly, _allocationAmount);
        IPandoAssembly(pandoAssembly).allocateMoreRewards(_allocationAmount, _days);
    }

    function emergencyWithdraw(address _token) external onlyOwner whenPaused {
        uint256 _amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setOperator(address _operator, bool _status) external onlyOwner {
        operators[_operator] = _status;
    }

    function setPandoAssembly(address _pandoAssembly) external onlyOwner {
        pandoAssembly = _pandoAssembly;
    }

    function setAllocationPercent(uint256 _allocationDailyPercent) external onlyOwner{
        allocationDailyPercent = _allocationDailyPercent;
    }
}