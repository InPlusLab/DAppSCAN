// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../perp/IPikaPerp.sol";
//SWC-135-Code With No Effects: L11-L140
contract PikaStaking is ReentrancyGuard, Pausable {

    using SafeERC20 for IERC20;
    using Address for address payable;

    address public owner;
    address public pikaPerp;
    address public rewardToken;
    address public stakingToken;
    uint256 public rewardTokenDecimal;

    uint256 public cumulativeRewardPerTokenStored;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => uint256) private claimableReward;
    mapping(address => uint256) private previousRewardPerToken;

    uint256 public constant PRECISION = 10**18;
    event ClaimedReward(
        address user,
        address rewardToken,
        uint256 amount
    );
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    constructor(address _stakingToken, address _rewardToken, uint256 _rewardTokenDecimal) {
        owner = msg.sender;
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        rewardTokenDecimal = _rewardTokenDecimal;
    }

    // Views methods

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    // Governance methods

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function setPikaPerp(address _pikaPerp) external onlyOwner {
        pikaPerp = _pikaPerp;
    }

    // Methods

    function stake(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Cannot stake 0");
        updateReward(msg.sender);
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant {
        require(amount > 0, "Cannot withdraw 0");
        updateReward(msg.sender);
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        IERC20(stakingToken).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function updateReward(address account) public {
        if (account == address(0)) return;
        uint256 pikaReward = IPikaPerp(pikaPerp).distributePikaReward();
        if (_totalSupply > 0) {
            cumulativeRewardPerTokenStored += pikaReward * PRECISION / _totalSupply;
        }
        if (cumulativeRewardPerTokenStored == 0) return;

        claimableReward[account] += _balances[account] * (cumulativeRewardPerTokenStored - previousRewardPerToken[account]) / PRECISION;
        previousRewardPerToken[account] = cumulativeRewardPerTokenStored;
    }

    function claimReward() external {
        updateReward(msg.sender);
        uint256 rewardToSend = claimableReward[msg.sender];
        claimableReward[msg.sender] = 0;
        if (rewardToSend > 0) {
            _transferOut(msg.sender, rewardToSend);
            emit ClaimedReward(
                msg.sender,
                rewardToken,
                rewardToSend
            );
        }
    }

    function getClaimableReward(address account) external view returns(uint256) {
        uint256 currentClaimableReward = claimableReward[account];
        if (_totalSupply == 0) return currentClaimableReward;

        uint256 _pendingReward = IPikaPerp(pikaPerp).getPendingPikaReward();
        uint256 _rewardPerTokenStored = cumulativeRewardPerTokenStored + _pendingReward * PRECISION / _totalSupply;
        if (_rewardPerTokenStored == 0) return currentClaimableReward;

        return currentClaimableReward + _balances[account] * (_rewardPerTokenStored - previousRewardPerToken[account]) / PRECISION;
    }

    fallback() external payable {}
    receive() external payable {}

    // Utils

    function _transferOut(address to, uint256 amount) internal {
        if (amount == 0 || to == address(0)) return;
        if (rewardToken == address(0)) {
            payable(to).sendValue(amount);
        } else {
            IERC20(rewardToken).safeTransfer(to, amount);
        }
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }
}
