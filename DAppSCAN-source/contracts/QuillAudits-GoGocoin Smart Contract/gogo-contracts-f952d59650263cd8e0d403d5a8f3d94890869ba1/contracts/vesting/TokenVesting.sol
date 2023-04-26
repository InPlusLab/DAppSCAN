// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract TokenVesting is Ownable {
	using SafeMath for uint256;

	struct VestingInfo {
		uint256 totalAmount;
		uint256 startTime;
		uint256 releaseInterval;
		uint256 totalReleaseCount;
		uint256 paidAmount;
	}

	uint256 totalVestingAmount;

	mapping(address => VestingInfo) vestingInfoMap;

	IERC20 public token;

	constructor(IERC20 _token) {
		require(address(_token) != address(0));
		token = _token;
		totalVestingAmount = 0;
	}

	modifier onlyRecipient() {
		require(vestingInfoMap[msg.sender].totalAmount != 0, "NOT_RECIPIENT");
		_;
	}

	function addVesting(
		address _recipient,
		uint256 _amount,
		uint256 _startTime,
		uint256 _releaseInterval,
		uint16 _releaseCount
	) external onlyOwner {
		require(!isVestingSet(_recipient), "VESTING_ALREADY_ADDED");
		require(_recipient != address(0), "RECIPIENT_NOT_VALID");
		require(_startTime > block.timestamp, "INVALID_START_TIME");
		require(_releaseInterval > 0, "INVALID_RELEASE_INTERVAL");
		require(_releaseCount > 0, "INVALID_RELEASE_COUNT");
		require(
			token.balanceOf(address(this)) >= totalVestingAmount.add(_amount),
			"INSUFFICIENT_TOKEN_BALANCE"
		);
		totalVestingAmount = totalVestingAmount.add(_amount);

		vestingInfoMap[_recipient] = VestingInfo(
			_amount,
			_startTime,
			_releaseInterval,
			_releaseCount,
			0
		);
	}

	function cancelVesting(address _recipient) external onlyOwner {
		require(!isVestingStarted(_recipient), "VESTING_ALREADY_STARTED");

		token.transfer(owner(), vestingInfoMap[_recipient].totalAmount);

		delete vestingInfoMap[_recipient];
	}

	function claim() external onlyRecipient {
		uint256 claimingAmount = claimableAmount(msg.sender);
		token.transfer(msg.sender, claimingAmount);
		vestingInfoMap[msg.sender].paidAmount = vestingInfoMap[msg.sender]
		.paidAmount
		.add(claimingAmount);
		totalVestingAmount = claimingAmount.sub(claimingAmount);
	}

	function claimableAmount(address _recipient)
		public
		view
		onlyRecipient
		returns (uint256)
	{
		VestingInfo memory info = vestingInfoMap[_recipient];
		if (info.startTime > block.timestamp) return 0;

		uint256 elapsedTime = block.timestamp.sub(info.startTime);
		// Check if all releases are gone
		uint256 totalApproved = amountPerRelease(_recipient).mul(
			Math.min(
				elapsedTime.div(info.releaseInterval),
				info.totalReleaseCount
			)
		);
		return totalApproved.sub(info.paidAmount);
	}

	function amountPerRelease(address _recipient)
		public
		view
		returns (uint256)
	{
		VestingInfo memory info = vestingInfoMap[_recipient];
		return info.totalAmount.div(info.totalReleaseCount);
	}

	function nextReleaseTimestamp()
		public
		view
		onlyRecipient
		returns (uint256)
	{
		VestingInfo memory info = vestingInfoMap[msg.sender];
		if (!isVestingSet(msg.sender)) {
			return 0;
		}

		if (!isVestingStarted(msg.sender)) {
			return info.startTime.add(info.releaseInterval);
		}

		uint256 elapsedTime = block.timestamp.sub(info.startTime);
		uint256 pastReleaseCount = elapsedTime.div(info.releaseInterval);

		if (pastReleaseCount > info.totalReleaseCount) {
			return 0;
		}
		return
			info.startTime.add(info.releaseInterval.mul(pastReleaseCount + 1));
	}

	function isVestingStarted(address _recipient) public view returns (bool) {
		return
			isVestingSet(_recipient) &&
			vestingInfoMap[_recipient].startTime <= block.timestamp;
	}

	function isVestingSet(address _recipient) internal view returns (bool) {
		return vestingInfoMap[_recipient].totalReleaseCount > 0;
	}
}
