// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IStaker.sol";
import "./interfaces/ITokenMinter.sol";
import "./interfaces/IVoteEscrow.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';


contract FxsDepositor{
    using SafeERC20 for IERC20;

    address public constant fxs = address(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    address public constant escrow = address(0xc8418aF6358FFddA74e09Ca9CC3Fe03Ca6aDC5b0);
    uint256 private constant MAXTIME = 4 * 364 * 86400;
    uint256 private constant WEEK = 7 * 86400;

    uint256 public lockIncentive = 0; //incentive to users who spend gas to lock
    uint256 public constant FEE_DENOMINATOR = 10000;

    address public feeManager;
    address public immutable staker;
    address public immutable minter;
    uint256 public incentiveFxs = 0;
    uint256 public unlockTime;

    constructor(address _staker, address _minter){
        staker = _staker;
        minter = _minter;
        feeManager = msg.sender;
    }

    function setFeeManager(address _feeManager) external {
        require(msg.sender == feeManager, "!auth");
        feeManager = _feeManager;
    }

    function setFees(uint256 _lockIncentive) external{
        require(msg.sender==feeManager, "!auth");

        if(_lockIncentive >= 0 && _lockIncentive <= 30){
            lockIncentive = _lockIncentive;
       }
    }

    function initialLock() external{
        require(msg.sender==feeManager, "!auth");

        uint256 vefxs = IERC20(escrow).balanceOf(staker);
        uint256 locked = IVoteEscrow(escrow).locked(staker);
        if(vefxs == 0 || vefxs == locked){
            uint256 unlockAt = block.timestamp + MAXTIME;
            uint256 unlockInWeeks = (unlockAt/WEEK)*WEEK;

            //release old lock if exists
            IStaker(staker).release();
            //create new lock
            uint256 fxsBalanceStaker = IERC20(fxs).balanceOf(staker);
            IStaker(staker).createLock(fxsBalanceStaker, unlockAt);
            unlockTime = unlockInWeeks;
        }
    }

    //lock curve
    function _lockFxs() internal {
        uint256 fxsBalance = IERC20(fxs).balanceOf(address(this));
        if(fxsBalance > 0){
            IERC20(fxs).safeTransfer(staker, fxsBalance);
        }
        
        //increase ammount
        uint256 fxsBalanceStaker = IERC20(fxs).balanceOf(staker);
        if(fxsBalanceStaker == 0){
            return;
        }
        
        //increase amount
        IStaker(staker).increaseAmount(fxsBalanceStaker);
        

        uint256 unlockAt = block.timestamp + MAXTIME;
        uint256 unlockInWeeks = (unlockAt/WEEK)*WEEK;

        //increase time too if over 1 week buffer
        if( unlockInWeeks - unlockTime >= 1){
            IStaker(staker).increaseTime(unlockAt);
            unlockTime = unlockInWeeks;
        }
    }

    function lockFxs() external {
        _lockFxs();

        //mint incentives
        if(incentiveFxs > 0){
            ITokenMinter(minter).mint(msg.sender,incentiveFxs);
            incentiveFxs = 0;
        }
    }

    //deposit fxs for cvxFxs
    //can locking immediately or defer locking to someone else by paying a fee.
    function deposit(uint256 _amount, bool _lock) public {
        require(_amount > 0,"!>0");
        
        if(_lock){
            //lock immediately, transfer directly to staker to skip an erc20 transfer
            IERC20(fxs).safeTransferFrom(msg.sender, staker, _amount);
            _lockFxs();
            if(incentiveFxs > 0){
                //add the incentive tokens here so they can be staked together
                _amount = _amount + incentiveFxs;
                incentiveFxs = 0;
            }
        }else{
            //move tokens here
            IERC20(fxs).safeTransferFrom(msg.sender, address(this), _amount);
            //defer lock cost to another user
            if(lockIncentive > 0){
                uint256 callIncentive = _amount * lockIncentive / FEE_DENOMINATOR;
                _amount = _amount - callIncentive;

                //add to a pool for lock caller
                incentiveFxs = incentiveFxs + callIncentive;
            }
        }

        //mint for msg.sender
        ITokenMinter(minter).mint(msg.sender,_amount);
    }

    function depositAll(bool _lock) external{
        uint256 fxsBal = IERC20(fxs).balanceOf(msg.sender);
        deposit(fxsBal,_lock);
    }
}