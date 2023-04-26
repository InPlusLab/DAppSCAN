// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../Constants.sol";
import  "../interfaces/IStrategy.sol";
import  "../interfaces/IFeeConf.sol";
import  "../interfaces/IController.sol";


/*
  if possible, strategies must remain as immutable as possible, instead of updating variables, update the contract by linking it in the controller
*/

abstract contract BaseStrategy is Constants, IStrategy, Ownable {
    using SafeERC20 for IERC20;
    
    address internal want; // such as: pancake lp 
    address public output; // such as: cake

    uint public minHarvestAmount;
    address public override controller;
    IFeeConf public feeConf;

    event Harvest(uint amount);
    event Deposit(uint amount);
    event Withdraw(uint amount);

    event SetController(address controller);
    event SetFeeConf(address controller);
    event SetMinHarvestAmount(uint harvestAmount);
    
    constructor(address _controller, address _fee, address _want, address _output) {
      controller = _controller;
      want = _want;
      output = _output;
      minHarvestAmount = 1e18;

      feeConf = IFeeConf(_fee);
    }

    function getWant() external view override returns (address){
      return want;
    }

    function balanceOf() external virtual view returns (uint256) {
      uint b = IERC20(want).balanceOf(address(this));
      return b + balanceOfPool();
    }

    function balanceOfPool() public virtual view returns (uint);

    // normally call from dToken.
    function deposit() public virtual;
    
    function harvest() external virtual;
    
    // Withdraw partial funds, normally used with a dToken withdrawal
    function withdraw(uint _amount) external virtual ;
    
    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external virtual returns (uint balance);
    
    function emergency() external virtual;

    // pending cake
    function pendingOutput() external virtual view returns (uint);
    

    function setMinHarvestAmount(uint _minAmount) external onlyOwner {
      minHarvestAmount = _minAmount;
      emit SetMinHarvestAmount(_minAmount);
    }

    function setController(address _controller) external onlyOwner {
      require(_controller != address(0), "INVALID_CONTROLLER");
      controller = _controller;
      emit SetController(_controller);
    }

    function setFeeConf(address _feeConf) external onlyOwner {
      require(_feeConf != address(0), "INVALID_FEECONF");
      feeConf = IFeeConf(_feeConf);
      emit SetFeeConf(_feeConf);
    }

    function inCaseTokensGetStuck(address _token, uint _amount) public onlyOwner {
      IERC20(_token).safeTransfer(owner(), _amount);
    }

    function safeTransfer(address _token, address _to, uint _amount) internal {
      uint b = IERC20(_token).balanceOf(address(this));
      if (b > _amount) {
        IERC20(_token).safeTransfer(_to, _amount);
      } else {
        IERC20(_token).safeTransfer(_to, b);
      }
    }
}