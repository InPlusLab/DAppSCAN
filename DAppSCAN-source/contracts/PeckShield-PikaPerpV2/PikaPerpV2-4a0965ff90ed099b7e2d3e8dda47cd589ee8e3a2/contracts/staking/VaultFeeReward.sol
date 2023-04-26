// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../perp/IPikaPerp.sol";

// PikaPerpV2 vault LPs can claim part of platform fee via this contract
// adapted from https://github.com/Synthetixio/synthetix/edit/develop/contracts/StakingRewards.sol
contract VaultFeeReward is ReentrancyGuard, Pausable {

    using SafeERC20 for IERC20;
    using Address for address payable;

    address public owner;
    address public pikaPerp;
    address public rewardToken;
    address public stakingToken;
    uint256 public rewardTokenDecimal;

    uint256 public cumulativeRewardPerTokenStored;

    mapping(address => uint256) private claimableReward;
    mapping(address => uint256) private previousRewardPerToken;

    uint256 public constant PRECISION = 10**18;
    uint256 public constant BASE = 10**8;

    event ClaimedReward(
        address user,
        address rewardToken,
        uint256 amount
    );
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    constructor(address _pikaPerp, address _rewardToken, uint256 _rewardTokenDecimal) {
        owner = msg.sender;
        pikaPerp = _pikaPerp;
        rewardToken = _rewardToken;
        rewardTokenDecimal = _rewardTokenDecimal;
    }

    // Governance methods

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function setPikaPerp(address _pikaPerp) external onlyOwner {
        pikaPerp = _pikaPerp;
    }

    // Methods

    function updateReward(address account) public {
        if (account == address(0)) return;
        uint256 vaultReward = IPikaPerp(pikaPerp).distributeVaultReward();
        uint256 supply = IPikaPerp(pikaPerp).getTotalShare();
        if (supply > 0) {
            cumulativeRewardPerTokenStored += vaultReward * PRECISION / supply;
        }
        if (cumulativeRewardPerTokenStored == 0) return;

        claimableReward[account] += IPikaPerp(pikaPerp).getShare(account) * (cumulativeRewardPerTokenStored - previousRewardPerToken[account]) / PRECISION;
        previousRewardPerToken[account] = cumulativeRewardPerTokenStored;
    }

    function claimReward() public returns(uint256 rewardToSend) {
        updateReward(msg.sender);
        rewardToSend = claimableReward[msg.sender];
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

    function reinvest() external {
        uint256 claimedReward = claimReward();
        IPikaPerp(pikaPerp).stake(claimedReward * BASE / rewardTokenDecimal);
    }

    function getClaimableReward(address account) external view returns(uint256) {
        uint256 currentClaimableReward = claimableReward[account];
        uint256 supply = IPikaPerp(pikaPerp).getTotalShare();
        if (supply == 0) return currentClaimableReward;

        uint256 _pendingReward = IPikaPerp(pikaPerp).getPendingVaultReward();
        uint256 _rewardPerTokenStored = cumulativeRewardPerTokenStored + _pendingReward * PRECISION / supply;
        if (_rewardPerTokenStored == 0) return currentClaimableReward;

        return currentClaimableReward + IPikaPerp(pikaPerp).getShare(account) * (_rewardPerTokenStored - previousRewardPerToken[account]) / PRECISION;
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
