// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../interfaces/IBasePool.sol";
import "../interfaces/ITimeLockPool.sol";

import "./AbstractRewards.sol";
import "./TokenSaver.sol";

abstract contract BasePool is ERC20Votes, AbstractRewards, IBasePool, TokenSaver {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using SafeCast for int256;

    IERC20 public immutable depositToken;
    IERC20 public immutable rewardToken;
    ITimeLockPool public immutable escrowPool;
    uint256 public immutable escrowPortion; // how much is escrowed 1e18 == 100%
    uint256 public immutable escrowDuration; // escrow duration in seconds

    event RewardsClaimed(address indexed _from, address indexed _receiver, uint256 _escrowedAmount, uint256 _nonEscrowedAmount);

    constructor(
        string memory _name,
        string memory _symbol,
        address _depositToken,
        address _rewardToken,
        address _escrowPool,
        uint256 _escrowPortion,
        uint256 _escrowDuration
    ) ERC20Permit(_name) ERC20(_name, _symbol) AbstractRewards(balanceOf, totalSupply) {
        require(_escrowPortion <= 1e18, "BasePool.constructor: Cannot escrow more than 100%");
        require(_depositToken != address(0), "BasePool.constructor: Deposit token must be set");
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
        escrowPool = ITimeLockPool(_escrowPool);
        escrowPortion = _escrowPortion;
        escrowDuration = _escrowDuration;

        if(_rewardToken != address(0) && _escrowPool != address(0)) {
            //SWC-Unchecked Call Return Value: L47
            IERC20(_rewardToken).safeApprove(_escrowPool, type(uint256).max);
        }
    }
    //SWC-Integer Overflow and Underflow: L51-L54
    function _mint(address _account, uint256 _amount) internal virtual override {
		super._mint(_account, _amount);
        _correctPoints(_account, -(_amount.toInt256()));
	}
	//SWC-Integer Overflow and Underflow: L56-L59
	function _burn(address _account, uint256 _amount) internal virtual override {
		super._burn(_account, _amount);
        _correctPoints(_account, _amount.toInt256());
	}

    function _transfer(address _from, address _to, uint256 _value) internal virtual override {
		super._transfer(_from, _to, _value);
        _correctPointsForTransfer(_from, _to, _value);
	}

    function distributeRewards(uint256 _amount) external override {
        rewardToken.safeTransferFrom(_msgSender(), address(this), _amount);
        _distributeRewards(_amount);
    }

    function claimRewards(address _receiver) external {
        uint256 rewardAmount = _prepareCollect(_msgSender());
        uint256 escrowedRewardAmount = rewardAmount * escrowPortion / 1e18;
        uint256 nonEscrowedRewardAmount = rewardAmount - escrowedRewardAmount;

        if(escrowedRewardAmount != 0 && address(escrowPool) != address(0)) {
            escrowPool.deposit(escrowedRewardAmount, escrowDuration, _receiver);
        }

        // ignore dust
        if(nonEscrowedRewardAmount > 1) {
            //SWC-Unchecked Call Return Value: L83
            rewardToken.safeTransfer(_receiver, nonEscrowedRewardAmount);
        }

        emit RewardsClaimed(_msgSender(), _receiver, escrowedRewardAmount, nonEscrowedRewardAmount);
    }

}