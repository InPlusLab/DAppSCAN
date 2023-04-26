// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {IDetailedERC20} from "../interfaces/IDetailedERC20.sol";
import {IMintableERC20} from "../interfaces/IMintableERC20.sol";

contract AlpacaStakingPoolMock {
    using SafeERC20 for IDetailedERC20;
    using SafeERC20 for IMintableERC20;
    using SafeMath for uint256;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many Staking tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 bonusDebt; // Last block that user exec something to the 
        address fundedBy; // Funded by who?
        //
        // We do some fancy math here. Basically, any point in time, the amount of ALPACAs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * accAlpacaPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws Staking tokens to a  Here's what happens:
        //   1. The pool's `accAlpacaPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    IDetailedERC20 public token;
    IMintableERC20 public rewardToken;
    uint256 public rewardPerBlock;
    uint256 public lastRewardBlock;
    uint256 public bonusEndBlock;
    uint256 public bonusMultiplier;
    uint256 public totalAllocPoint;
    uint256 public allocPoint;
    uint256 public totalDeposited;
    uint256 public accAlpacaPerShare;
    uint256 public accAlpacaPerShareTilBonusEnd;

    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    constructor(IDetailedERC20 _token, IMintableERC20 _rewardToken, uint256 _rewardPerBlock) public {
        token = _token;
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        bonusMultiplier = 0;
        totalAllocPoint = 100;
        allocPoint = 10;
    }

    function deposit(address _for, uint256 _pid, uint256 _amount) external returns (uint256) {
        UserInfo storage user = userInfo[_pid][_for];
        if (user.fundedBy != address(0)) require(user.fundedBy == msg.sender, "bad sof");
        if (user.fundedBy == address(0)) user.fundedBy = msg.sender;
        if (user.amount > 0) _harvest(_for, _pid);

        token.safeTransferFrom(msg.sender, address(this), _amount);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(accAlpacaPerShare).div(1e12);
        user.bonusDebt = user.amount.mul(accAlpacaPerShareTilBonusEnd).div(1e12);
        totalDeposited = totalDeposited.add(_amount);
        updatePool();
    }

    function withdraw(address _for, uint256 _pid, uint256 _amount) external returns (uint256) {
        UserInfo storage user = userInfo[_pid][_for];
        require(user.fundedBy == msg.sender, "bad sof");
        require(user.amount >= _amount, "bad amount");
        updatePool();
        _harvest(_for, _pid);

        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(accAlpacaPerShare).div(1e12);
        SafeERC20.safeTransfer(token, msg.sender, _amount);
        totalDeposited = totalDeposited.sub(_amount);
    }

    // Harvest ALPACAs earn from the 
    function harvest(uint256 _pid) public {
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool();
        _harvest(msg.sender, _pid);
        user.rewardDebt = user.amount.mul(accAlpacaPerShare).div(1e12);
    }

    function _harvest(address _to, uint256 _pid) internal {
        UserInfo storage user = userInfo[_pid][_to];
        require(user.amount > 0, "nothing to harvest");
        uint256 pending = user.amount.mul(accAlpacaPerShare).div(1e12).sub(user.rewardDebt);
        require(pending <= rewardToken.balanceOf(address(this)), "wtf not enough alpaca");
        rewardToken.safeTransfer(_to, pending);
    }

    function getMultiplier(uint256 _lastRewardBlock, uint256 _currentBlock) public view returns (uint256) {
        if (_currentBlock <= bonusEndBlock) {
        return _currentBlock.sub(_lastRewardBlock).mul(bonusMultiplier);
        }
        if (_lastRewardBlock >= bonusEndBlock) {
        return _currentBlock.sub(_lastRewardBlock);
        }
        // This is the case where bonusEndBlock is in the middle of _lastRewardBlock and _currentBlock block.
        return bonusEndBlock.sub(_lastRewardBlock).mul(bonusMultiplier).add(_currentBlock.sub(bonusEndBlock));
    }


    function updatePool() public {
        if (block.number <= lastRewardBlock) {
            return;
        }
        uint256 lpSupply = IDetailedERC20(token).balanceOf(address(this));
        if (lpSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(lastRewardBlock, block.number);
        uint256 alpacaReward = multiplier.mul(rewardPerBlock).mul(allocPoint).div(totalAllocPoint);
        rewardToken.mint(address(this), alpacaReward);
        accAlpacaPerShare = accAlpacaPerShare.add(alpacaReward.mul(1e12).div(lpSupply));
        lastRewardBlock = block.number;
    }
}
