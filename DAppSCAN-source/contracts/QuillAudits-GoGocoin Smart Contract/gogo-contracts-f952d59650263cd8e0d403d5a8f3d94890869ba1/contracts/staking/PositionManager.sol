// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "./StakingRewardsLP.sol";

contract PositionManager is Ownable {
	using SafeMath for uint256;

	struct PositionInfo {
		// represents StakingRewardsLP contract address
		address positionAddress;
		address stakingTokenAddress;
		address rewardsTokenAddress;
	}

	mapping(address => bool) public positionExists;
	mapping(address => uint256) public positionIndices;
	PositionInfo[] public positions;

	event PositionAdded(
		address positionAddress,
		address stakingTokenAddress,
		/*string stakingTokenSymbol,*/
		address rewardsTokenAddress /*, string rewardsTokenSymbol*/
	);
	event PositionRemoved(address positionAddress);
	event AllPositionsRemoved();

	// constructor() public {}

	function addPosition(address positionAddress) public onlyOwner {
		require(
			!positionExists[positionAddress],
			"This position already exists"
		);

		StakingRewardsLP _position = StakingRewardsLP(positionAddress);
		IERC20 stakingToken = _position.stakingToken();
		IERC20 rewardsToken = _position.rewardsToken();

		PositionInfo memory _positionInfo;
		_positionInfo.positionAddress = positionAddress;
		_positionInfo.stakingTokenAddress = address(stakingToken);
		_positionInfo.rewardsTokenAddress = address(rewardsToken);

		positionIndices[positionAddress] = positions.length;
		positions.push(_positionInfo);
		positionExists[positionAddress] = true;

		emit PositionAdded(
			positionAddress,
			_positionInfo.stakingTokenAddress,
			_positionInfo.rewardsTokenAddress
		);
	}

	function removePosition(address positionAddress) public onlyOwner {
		require(
			positionExists[positionAddress],
			"Can't remove what's not there. Position doesn't exist"
		);

		uint256 idx = positionIndices[positionAddress];
		positionExists[positionAddress] = false;
		positions[idx] = positions[positions.length - 1];
		positions.pop();

		// delete mapping to array for the element being removed
		delete positionIndices[positionAddress];

		// if the element being removed was not the last one in array (so that other element actually moved)
		if (idx != positions.length) {
			// update mapping for the moved element
			positionIndices[positions[idx].positionAddress] = idx;
		}

		emit PositionRemoved(positionAddress);
	}

	function getPositionsCount() public view returns (uint256) {
		return positions.length;
	}

	function earnedAcrossPositions(address account)
		public
		view
		returns (uint256)
	{
		uint256 totalEarned = 0;
		for (uint256 i = 0; i < positions.length; i++) {
			totalEarned = totalEarned.add(
				StakingRewardsLP(positions[i].positionAddress).earned(account)
			);
		}
		return totalEarned;
	}

	function removeAllPositions() public onlyOwner {
		for (uint256 i = 0; i < positions.length; i++) {
			positionIndices[positions[i].positionAddress] = 0; // same as 'delete positionIndices[positions[i].positionAddress]'
			positionExists[positions[i].positionAddress] = false;
		}
		delete positions;
		emit AllPositionsRemoved();
	}

	function claimAllRewards() public {
		for (uint256 i = 0; i < positions.length; i++) {
			StakingRewardsLP(positions[i].positionAddress).getRewardFor(
				msg.sender
			);
		}
	}
}
