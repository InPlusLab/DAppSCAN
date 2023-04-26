// SPDX-License-Identifier: MIT

pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "hardhat/console.sol";

contract HoldStake is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct HoldPool {
        IERC20 token;
        uint256 hardcap;
        uint256 preUserHardcap;
        uint256 apy; //100% = 1 * 10**6
        uint256 depositTotal;
        uint256 interest;
        uint256 finishTime;
    }

    struct DepositInfo {
        uint256 pid;
        uint256 value;
        uint256 duration;
        uint256 earned;
        uint256 unlockTime;
        bool present;
    }

    mapping(uint256 => uint256) private finalCompleTime;

    mapping(uint256 => uint256) private interestHardcap;
    mapping(uint256 => address) public interestProvider;

    mapping(uint256 => uint256) public lockDuration;
    mapping(uint256 => HoldPool) public holdPools;
    mapping(address => mapping(uint256 => DepositInfo)) public depositInfos;
    uint256 public pid;

    event AddHoldPool(
        uint256 pid,
        address token,
        uint256 hardcap,
        uint256 preUserHardcap,
        uint256 apy
    );

    event Deposit(
        uint256 indexed pid,
        address indexed account,
        uint256 indexed duration,
        uint256 value
    );

    event Harvest(uint256 indexed pid, address indexed account, uint256 earned);

    event Withdraw(uint256 indexed pid, address indexed account, uint256 value);

    event AnnounceEndTime(uint256 indexed pid, uint256 indexed finishTime);

    event InterestInjection(
        uint256 indexed pid,
        address indexed provider,
        uint256 value
    );
    event InterestRefund(
        uint256 indexed pid,
        address indexed recipient,
        uint256 value
    );

    constructor() {
        lockDuration[1] = 15 days;
        lockDuration[2] = 30 days;
        lockDuration[3] = 60 days;
        lockDuration[4] = 90 days;
    }

    function addPool(
        IERC20 token,
        uint256 hardcap,
        uint256 preUserHardcap,
        uint256 apy
    ) external onlyOwner {
        require(address(token) != address(0), "Hold: Token address is zero");
        token.balanceOf(address(this)); //Check ERC20
        pid++;
        HoldPool storage holdPool = holdPools[pid];
        holdPool.apy = apy;
        holdPool.token = token;
        holdPool.hardcap = hardcap;
        holdPool.preUserHardcap = preUserHardcap;

        emit AddHoldPool(pid, address(token), hardcap, preUserHardcap, apy);
    }

    function injectInterest(uint256 _pid) external {
        require(_pid > 0 && _pid <= pid, "Hold: Can't find this pool");
        HoldPool memory holdPool = holdPools[_pid];
        require(
            interestHardcap[_pid] == 0 && interestProvider[_pid] == address(0),
            "Hold: The pool interest has been injected"
        );
        uint256 interestTotal = holdPool
            .hardcap
            .mul(holdPool.apy)
            .mul(lockDuration[4])
            .div(365 days)
            .div(1e6);
        interestHardcap[_pid] = interestTotal;
        interestProvider[_pid] = msg.sender;
        holdPool.token.safeTransferFrom(
            msg.sender,
            address(this),
            interestTotal
        );

        emit InterestInjection(_pid, msg.sender, interestTotal);
    }

    function deposit(
        uint256 _pid,
        uint256 value,
        uint256 opt
    ) external checkFinish(_pid, lockDuration[opt]) {
        require(_pid > 0 && _pid <= pid, "Hold: Can't find this pool");
        require(lockDuration[opt] > 0, "Hold: Without this option");
        require(
            holdPools[_pid].depositTotal < holdPools[_pid].hardcap,
            "Hold: Hard cap limit"
        );
        if (holdPools[_pid].depositTotal.add(value) > holdPools[_pid].hardcap) {
            value = holdPools[_pid].hardcap.sub(holdPools[_pid].depositTotal);
        }
        require(
            value <= holdPools[_pid].preUserHardcap,
            "Hold: Personal hard cap limit"
        );
        require(
            !depositInfos[msg.sender][_pid].present,
            "Hold: Individuals can only invest once at the same time"
        );
        holdPools[_pid].depositTotal = holdPools[_pid].depositTotal.add(value);
        depositInfos[msg.sender][_pid].present = true;
        depositInfos[msg.sender][_pid].value = value;
        depositInfos[msg.sender][_pid].pid = _pid;
        depositInfos[msg.sender][_pid].duration = lockDuration[opt];
        depositInfos[msg.sender][_pid].unlockTime = lockDuration[opt].add(
            block.timestamp
        );
        depositInfos[msg.sender][_pid].earned = value
            .mul(holdPools[_pid].apy)
            .mul(lockDuration[opt])
            .div(365 days)
            .div(1e6);
        holdPools[_pid].interest = holdPools[_pid].interest.add(
            depositInfos[msg.sender][_pid].earned
        );
        holdPools[_pid].token.safeTransferFrom(
            msg.sender,
            address(this),
            value
        );
        emit Deposit(_pid, msg.sender, lockDuration[opt], value);
    }

    function harvest(uint256 _pid) external {
        require(_pid > 0 && _pid <= pid, "Hold: Can't find this pool");
        DepositInfo storage depositInfo = depositInfos[msg.sender][_pid];
        require(
            block.timestamp > depositInfo.unlockTime,
            "Hold: Unlocking time is not reached"
        );
        require(depositInfo.earned > 0, "Hold: There is no income to receive");
        uint256 earned = depositInfo.earned;
        depositInfo.earned = 0;
        holdPools[depositInfo.pid].token.safeTransfer(msg.sender, earned);

        emit Harvest(depositInfo.pid, msg.sender, earned);
    }

    function withdraw(uint256 _pid) external {
        require(_pid > 0 && _pid <= pid, "Hold: Can't find this pool");
        DepositInfo storage depositInfo = depositInfos[msg.sender][_pid];
        require(
            block.timestamp > depositInfo.unlockTime,
            "Hold: Unlocking time is not reached"
        );
        require(depositInfo.value > 0, "Hold: There is no deposit to receive");
        uint256 value = depositInfo.value;
        depositInfo.value = 0;
        depositInfo.present = false;
        holdPools[depositInfo.pid].token.safeTransfer(msg.sender, value);
        emit Withdraw(depositInfo.pid, msg.sender, value);
    }

    modifier checkFinish(uint256 _pid, uint256 duration) {
        _;
        if (block.timestamp.add(duration) > finalCompleTime[_pid]) {
            finalCompleTime[_pid] = block.timestamp.add(duration);
        }
        if (holdPools[_pid].hardcap == holdPools[_pid].depositTotal) {
            holdPools[_pid].finishTime = finalCompleTime[_pid];
            emit AnnounceEndTime(_pid, holdPools[_pid].finishTime);

            uint256 interestLeft = interestHardcap[_pid].sub(
                holdPools[_pid].interest
            );
            if (interestLeft > 0) {
                holdPools[_pid].token.safeTransfer(
                    interestProvider[_pid],
                    interestLeft
                );
                emit InterestRefund(_pid, interestProvider[_pid], interestLeft);
            }
        }
    }

    function holdInProgress() external view returns (HoldPool[] memory) {
        uint256 len;
        for (uint256 i = 1; i <= pid; i++) {
            if (holdPools[i].finishTime > block.timestamp) {
                len++;
            }
        }
        HoldPool[] memory pools = new HoldPool[](len);
        for (uint256 i = 1; i <= pid; i++) {
            if (holdPools[i].finishTime > block.timestamp) {
                pools[i] = holdPools[i];
            }
        }
        return pools;
    }

    function holdInFinished() external view returns (HoldPool[] memory) {
        uint256 len;
        for (uint256 i = 1; i <= pid; i++) {
            if (holdPools[i].finishTime <= block.timestamp) {
                len++;
            }
        }
        HoldPool[] memory pools = new HoldPool[](len);
        for (uint256 i = 1; i <= pid; i++) {
            if (holdPools[i].finishTime <= block.timestamp) {
                pools[i] = holdPools[i];
            }
        }
        return pools;
    }
}
