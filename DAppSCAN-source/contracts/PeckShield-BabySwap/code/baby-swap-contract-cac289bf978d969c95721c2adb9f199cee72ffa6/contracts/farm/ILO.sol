// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

import '../libraries/SafeMath.sol';
import '../interfaces/IBEP20.sol';
import '../token/SafeBEP20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import 'hardhat/console.sol';

import "../token/BabyToken.sol";
import "./SyrupBar.sol";

// import "@nomiclabs/buidler/console.sol";

contract ILO is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    struct UserInfo {
        uint256 amount;     
        uint256 lastTime;
    }
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. CAKEs to distribute per block.
        uint256 totalAmount;
    }

    BabyToken public cake;

    PoolInfo[] public poolInfo;
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    uint256 public totalAllocPoint = 0;
    uint256 public startBlock;
    uint256 public endBlock;
    
    function setStartBlock(uint256 blockNumber) public onlyOwner {
        startBlock = blockNumber;
    }

    function setEndBlock(uint256 blockNumber) public onlyOwner {
        endBlock = blockNumber;
    }
    
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        BabyToken _cake,
        uint256 _startBlock,
        uint256 _endBlock
    ) {
        cake = _cake;
        startBlock = _startBlock;
        endBlock = _endBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function add(uint256 _allocPoint, IBEP20 _lpToken) external onlyOwner {
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            totalAmount: 0
        }));
    }

    function pendingBaby(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 balance = cake.balanceOf(address(this));
        if (balance == 0) {
            return 0; 
        }
        uint256 poolBalance = balance.mul(pool.allocPoint).div(totalAllocPoint);
        if (poolBalance == 0) {
            return 0;
        }
        if (pool.totalAmount == 0) {
            return 0;
        }
        return balance.mul(pool.allocPoint).mul(user.amount).div(totalAllocPoint).div(pool.totalAmount);
    }

    function deposit(uint256 _pid, uint256 _amount) external {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(block.number >= startBlock, "ILO not begin");
        require(block.number <= endBlock, "ILO already finish");
        require(_amount > 0, "illegal amount");

        //if (_amount > 0) {
            user.amount = user.amount.add(_amount);
            user.lastTime = block.timestamp;
            pool.totalAmount = pool.totalAmount.add(_amount);
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        //}

        emit Deposit(msg.sender, _pid, _amount);
    }



    function withdraw(uint256 _pid) external {
        require(block.number > endBlock, "Can not claim now");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 pendingAmount = pendingBaby(_pid, msg.sender);
        if (pendingAmount > 0) {
            safeCakeTransfer(msg.sender, pendingAmount);
            emit Claim(msg.sender, _pid, pendingAmount);
        }
        if (user.amount > 0) {
            uint _amount = user.amount;
            user.amount = 0;
            user.lastTime = block.timestamp;
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            emit Withdraw(msg.sender, _pid, _amount);
        }
    }

    function ownerWithdraw(address _to, uint256 _amount) public onlyOwner {
        require(block.number < startBlock || block.number >= endBlock + 403200, "ILO already start");  //after a week can withdraw
        safeCakeTransfer(_to, _amount);
    }

    // Safe cake transfer function, just in case if rounding error causes pool to not have enough CAKEs.
    function safeCakeTransfer(address _to, uint256 _amount) internal {
        uint256 balance = cake.balanceOf(address(this));
        if (_amount > balance) {
            _amount = balance;
        }
        IBEP20(address(cake)).safeTransfer(_to, _amount);
    }

}
