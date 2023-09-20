// SPDX-License-Identifier: https://github.com/lendroidproject/protocol.2.0/blob/master/LICENSE.md
pragma solidity 0.7.4;

import "@openzeppelin/contracts/math/Math.sol";
import "../heartbeat/Pacemaker.sol";
import "./LPTokenWrapper.sol";


/** @title BasePool
    @author Lendroid Foundation
    @notice Inherits the LPTokenWrapper contract, performs additional functions
        on the stake and unstake functions, and includes logic to calculate and
        withdraw rewards.
        This contract is inherited by all Pool contracts.
    @dev Audit certificate : Pending
*/


abstract contract BasePool is LPTokenWrapper, Pacemaker {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    string public poolName;
    IERC20 public rewardToken;

    mapping(uint256 => uint256) private _totalBalancesPerEpoch;
    mapping(address => mapping(uint256 => uint256)) private _balancesPerEpoch;
    mapping(address => uint256) public lastEpochStaked;
    mapping(address => uint256) public lastEpochRewardsClaimed;

    uint256 public starttime = HEARTBEATSTARTTIME;// 2020-12-04 00:00:00 (UTC UTC +00:00)

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    /**
        @notice Registers the Pool name, Reward Token address, and LP Token address.
        @param name : Name of the Pool
        @param rewardTokenAddress : address of the Reward Token
        @param lpTokenAddress : address of the LP Token
    */
    constructor(string memory name, address rewardTokenAddress, address lpTokenAddress) LPTokenWrapper(lpTokenAddress) {
        rewardToken = IERC20(rewardTokenAddress);
        poolName = name;
    }

    /**
        @notice modifier to check if the starttime has been reached
    */
    modifier checkStart(){
        require(block.timestamp >= starttime,"not start");
        _;
    }

    /**
        @notice Displays total reward tokens available for a given epoch. This
        function is implemented in contracts that inherit this contract.
    */
    function totalRewardsInEpoch(uint256 epoch) virtual pure public returns (uint256 totalRewards);

    /**
        @notice Stake / Deposit LP Token into the Pool.
        @dev Increases count of total LP Token staked in the current epoch.
             Increases count of LP Token staked for the caller in the current epoch.
             Register that caller last staked in the current epoch.
             Perform actions from BasePool.stake().
        @param amount : Amount of LP Token to stake
    */
    function stake(uint256 amount) public checkStart override {
        require(amount > 0, "Cannot stake 0");
        _balancesPerEpoch[msg.sender][_currentEpoch()] = _balancesPerEpoch[msg.sender][_currentEpoch()].add(amount);
        _totalBalancesPerEpoch[_currentEpoch()] = _totalBalancesPerEpoch[_currentEpoch()].add(amount);
        lastEpochStaked[msg.sender] = _currentEpoch();
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    /**
        @notice Unstake / Withdraw staked LP Token from the Pool
        @inheritdoc LPTokenWrapper
    */
    function unstake(uint256 amount) public checkStart override {
        require(amount > 0, "Cannot unstake 0");
        require(lastEpochStaked[msg.sender] < _currentEpoch(), "Cannot unstake if staked during current epoch.");
        super.unstake(amount);
        emit Unstaked(msg.sender, amount);
    }

    /**
        @notice Unstake the staked LP Token and claim corresponding earnings from the Pool
        @dev : Perform actions from unstake()
               Perform actions from claim()
    */
    function unstakeAndClaim() checkStart external {
        unstake(balanceOf(msg.sender));
        claim();
    }

    /**
        @notice Displays earnings of a given address from previous epochs.
        @param account : the given user address
        @return earnings of given address since last withdrawn epoch
    */
    function earned(address account) public view returns (uint256 earnings) {
        earnings = 0;
        if (lastEpochStaked[account] > 0) {
            uint256 rewardPerEpoch = 0;
            for (uint256 epoch = lastEpochRewardsClaimed[account]; epoch < _currentEpoch(); epoch++) {
                if (_totalBalancesPerEpoch[epoch] > 0) {
                    rewardPerEpoch = _balancesPerEpoch[account][epoch].mul(totalRewardsInEpoch(epoch)).div(_totalBalancesPerEpoch[epoch]);
                    earnings = earnings.add(rewardPerEpoch);
                }
            }
        }
    }

    /**
        @notice Transfers earnings from previous epochs to the caller
    */
    //SWC-128-DoS With Block Gas Limit: L121-L128
    function claim() public checkStart {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            lastEpochRewardsClaimed[msg.sender] = _currentEpoch();
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardClaimed(msg.sender, reward);
        }
    }

}
