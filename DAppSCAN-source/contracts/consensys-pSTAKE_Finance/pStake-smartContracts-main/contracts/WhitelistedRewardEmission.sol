/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./interfaces/IWhitelistedRewardEmission.sol";
import "./interfaces/IHolderV2.sol";
import "./libraries/FullMath.sol";

contract WhitelistedRewardEmission is
	IWhitelistedRewardEmission,
	PausableUpgradeable,
	AccessControlUpgradeable
{
	using SafeMathUpgradeable for uint256;
	using FullMath for uint256;
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

	// constants defining access control ROLES
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
	// address of StakeLP contract
	address public _stakeLPContract;
	// valueDivisor to store fractional values for various reward attributes like _rewardTokenEmission
	uint256 public _valueDivisor;
	// variable pertaining to contract upgrades versioning
	uint256 public _version;

	// -------------------------------------------------------------------------
	// -------------------------------------------------------------------------

	// ::HOLDER WHITELISTINGS FOR OTHER REWARD TOKENS EMISSION::
	// List of Holder Contract Addresses
	EnumerableSetUpgradeable.AddressSet private _holderContractList;
	// list of reward tokens enabled, for a holder contract, for a reward token,
	mapping(address => address[]) public _rewardTokenList;
	// index of reward token address in the _rewardTokenList array, for the reward token, for the holder contract
	mapping(address => mapping(address => uint256))
		public _rewardTokenListIndex;
	// emission (per second) of reward token into the 'reward pool', for the reward token, for the holder contract
	mapping(address => mapping(address => uint256[]))
		public _rewardTokenEmission;
	// cummulative reward amount at the reward emission timestamp, for the reward token, for the holder contract
	mapping(address => mapping(address => uint256[]))
		public _cumulativeRewardAmount;
	// timestamp recorded when the emission (per second) of reward token is changed, for the reward token,
	// for the holder contract
	mapping(address => mapping(address => uint256[]))
		public _rewardEmissionTimestamp;
	// reward sink refers to a sink variable where extra rewards dropped gets stored when the current emission rate is 0
	// for the reward token, for the holder contract
	mapping(address => mapping(address => uint256)) public _rewardSink;

	// -------------------------------------------------------------------------
	// -------------------------------------------------------------------------

	// array of last recorded timestamp when total LPTimeShare was updated, for an LP Token
	mapping(address => uint256[]) public _lastLPTimeShareTimestampArray;
	// array of cummulative new supply LPTimeshare, for an LP Token
	mapping(address => uint256[]) public _cumulativeNewSupplyLPTimeShare;
	// the last timestamp when the updated reward pool was calculated,
	// for a user, for the reward token, for the holder contract
	mapping(address => mapping(address => mapping(address => uint256)))
		public _rewardPoolUserTimestamp;

	/**
	 * @dev Constructor for initializing the SToken contract.
	 * @param pauserAddress - address of the pauser admin.
	 * @param valueDivisor - valueDivisor set to 10^9.
	 */
	function initialize(address pauserAddress, uint256 valueDivisor)
		public
		virtual
		initializer
	{
		__AccessControl_init();
		__Pausable_init();
		_setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
		_setupRole(PAUSER_ROLE, pauserAddress);
		_valueDivisor = valueDivisor;
		_version = 1;
	}

	/*
	 * @dev add liquidity and reward tokens and disburse to user
	 * @param holderContractAddress: holder contract address
	 * @param rewardTokenContractAddress: reward token contract address
	 * @param rewardSender: sender address
	 * @param rewardAmount: token amount
	 */
	function addRewards(
		address holderContractAddress,
		address rewardTokenContractAddress,
		address rewardSender,
		uint256 rewardAmount
	) public override returns (bool success) {
		// require the message sender to be admin
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "WR1");
		// require the holder contract to be whitelisted for other reward tokens
		require(isHolderContractWhitelisted(holderContractAddress), "WR2");
		// require the reward token contract address be whitelisted for that holder contract
		require(
			_rewardTokenListIndex[holderContractAddress][
				rewardTokenContractAddress
			] != 0,
			"WR3"
		);
		// require reward sender and reward amounts not be zero values
		require(rewardSender != address(0) && rewardAmount != 0, "WR4");

		uint256[]
			storage _cumulativeRewardAmountArray = _cumulativeRewardAmount[
				holderContractAddress
			][rewardTokenContractAddress];
		uint256[]
			storage _rewardEmissionTimestampArray = _rewardEmissionTimestamp[
				holderContractAddress
			][rewardTokenContractAddress];
		uint256[] storage _rewardTokenEmissionArray = _rewardTokenEmission[
			holderContractAddress
		][rewardTokenContractAddress];
		uint256 arrayLength = _cumulativeRewardAmountArray.length;
		uint256 lastRewardAmount;
		uint256 updatedTimestampRemainder;
		uint256 updatedTimestamp;

		// Check if the array has at least one (or two ) entries, else skip the array updation
		// and directly transfer tokens to be allocated during first emission set, using balanceOf
		if (arrayLength > 0) {
			// array will be updated in twos. at least for the first time
			assert(arrayLength != 1);
			// if last timestamp is in the future (or exact present), then update the last entry
			if (
				_rewardEmissionTimestampArray[arrayLength.sub(1)] >=
				block.timestamp
			) {
				// get the reward diff in the last interval block
				lastRewardAmount = (
					_cumulativeRewardAmountArray[arrayLength.sub(1)]
				).sub(_cumulativeRewardAmountArray[arrayLength.sub(2)]);
				// assert that the reward diff is more than zero,
				// then add the diff to new amount and readjust timelines
				assert(lastRewardAmount > 0);
				// calculated the updated timestamp for the emission end using updated reward amount
				lastRewardAmount = lastRewardAmount.add(rewardAmount);
				// calculated updated timestamp which also includes any remainder emission at the end
				// also consider what next timestamp entry should be
				updatedTimestampRemainder = (
					(lastRewardAmount.mul(_valueDivisor)).mod(
						_rewardTokenEmissionArray[arrayLength.sub(2)]
					)
				).div(_valueDivisor);
				updatedTimestampRemainder = updatedTimestampRemainder > 0
					? 1
					: 0;

				updatedTimestamp = (
					(lastRewardAmount.mul(_valueDivisor)).div(
						_rewardTokenEmissionArray[arrayLength.sub(2)]
					)
				).add(updatedTimestampRemainder).add(
						_rewardEmissionTimestampArray[arrayLength.sub(2)]
					);
				// update the timestamp endpoint for emission end to state variable
				_rewardEmissionTimestampArray[
					arrayLength.sub(1)
				] = updatedTimestamp;
				// update the cumulative reward amount for emission end to state variable
				_cumulativeRewardAmountArray[
					arrayLength.sub(1)
				] = lastRewardAmount.add(
					_cumulativeRewardAmountArray[arrayLength.sub(2)]
				);
			} else {
				// if last timestamp is in the past, then it means the current emission rate is 0,
				// so drop the reward in the sink and wait for emission rate to be set non-zero
				lastRewardAmount = _rewardSink[holderContractAddress][
					rewardTokenContractAddress
				];
				_rewardSink[holderContractAddress][
					rewardTokenContractAddress
				] = lastRewardAmount.add(rewardAmount);
			}
		}

		// transfer the reward tokens from the sender address to the holder contract address
		// this requires the amount to be approved for transfer as a pre-condition
		IHolderV2(holderContractAddress).safeTransferFrom(
			rewardTokenContractAddress,
			rewardSender,
			holderContractAddress,
			rewardAmount
		);

		emit AddRewards(
			holderContractAddress,
			rewardTokenContractAddress,
			rewardSender,
			rewardAmount,
			block.timestamp
		);

		success = true;
	}

	/*
	 * @dev set reward emission
	 * @param holderContractAddress: holder contract address
	 * @param rewardTokenContractAddress: reward token contract address
	 * @param rewardTokenEmission: token amount
	 */
	function setRewardEmission(
		address holderContractAddress,
		address rewardTokenContractAddress,
		uint256 rewardTokenEmission
	) public override returns (bool success) {
		// require the message sender to be admin
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "WR5");
		// require the holder contract to be whitelisted for other reward tokens
		require(isHolderContractWhitelisted(holderContractAddress), "WR6");
		// require the reward token contract address be whitelisted for that holder contract
		require(
			_rewardTokenListIndex[holderContractAddress][
				rewardTokenContractAddress
			] != 0,
			"WR7"
		);

		uint256[]
			storage _cumulativeRewardAmountArray = _cumulativeRewardAmount[
				holderContractAddress
			][rewardTokenContractAddress];
		uint256[]
			storage _rewardEmissionTimestampArray = _rewardEmissionTimestamp[
				holderContractAddress
			][rewardTokenContractAddress];
		uint256[] storage _rewardTokenEmissionArray = _rewardTokenEmission[
			holderContractAddress
		][rewardTokenContractAddress];
		uint256 arrayLength = _cumulativeRewardAmountArray.length;
		uint256 rewardAmount;
		uint256 remainingRewardAmount;
		uint256 updatedTimestampRemainder;
		uint256 updatedTimestamp;
		uint256 timeInterval;
		// Check if the array has at least one (or two) entries. If so alter the penultimate or endpoint entry
		if (arrayLength > 0) {
			// array will be updated in twos. at least for the first time
			assert(arrayLength != 1);
			// if timestamp endpoint is in the future (or exact present), then update the last entry
			if (
				_rewardEmissionTimestampArray[arrayLength.sub(1)] >
				block.timestamp
			) {
				// if the provided new emission rate is same as previous then revert
				require(
					rewardTokenEmission !=
						_rewardTokenEmissionArray[arrayLength.sub(2)],
					"WR8"
				);
				// if current time is equal to the penultimate marker then
				// update both the penultimate entry and the endpoint entry
				if (
					block.timestamp ==
					_rewardEmissionTimestampArray[arrayLength.sub(2)]
				) {
					// get the reward diff in the last interval block
					rewardAmount = (
						_cumulativeRewardAmountArray[arrayLength.sub(1)]
					).sub(_cumulativeRewardAmountArray[arrayLength.sub(2)]);
					// assert that the reward diff is more than zero,
					assert(rewardAmount > 0);

					// set the penultimate emission value
					_rewardTokenEmissionArray[
						arrayLength.sub(2)
					] = rewardTokenEmission;

					if (rewardTokenEmission > 0) {
						// calculate the time interval across which emission will happen
						updatedTimestampRemainder = (
							(rewardAmount.mul(_valueDivisor)).mod(
								rewardTokenEmission
							)
						).div(_valueDivisor);
						updatedTimestampRemainder = updatedTimestampRemainder >
							0
							? 1
							: 0;

						updatedTimestamp = (
							(
								(rewardAmount.mul(_valueDivisor)).div(
									rewardTokenEmission
								)
							).add(updatedTimestampRemainder)
						).add(block.timestamp);

						// set the endpoint timestamp value
						_rewardEmissionTimestampArray[
							arrayLength.sub(1)
						] = updatedTimestamp;
					} else {
						// move the remnant reward amount to sink
						_rewardSink[holderContractAddress][
							rewardTokenContractAddress
						] += rewardAmount;

						// remove the endpoint reward amount
						_cumulativeRewardAmount[holderContractAddress][
							rewardTokenContractAddress
						].pop();
						// remove the endpoint reward emission
						_rewardTokenEmission[holderContractAddress][
							rewardTokenContractAddress
						].pop();
						// remove the endpoint reward timestamp
						_rewardEmissionTimestamp[holderContractAddress][
							rewardTokenContractAddress
						].pop();
					}

					// if current time is more than penultimate marker then update
					// endpoint marker and add new element as the new endpoint
				} else {
					timeInterval = block.timestamp.sub(
						_rewardEmissionTimestampArray[arrayLength.sub(2)]
					);

					rewardAmount = timeInterval.mulDiv(
						_rewardTokenEmissionArray[arrayLength.sub(2)],
						_valueDivisor
					);

					remainingRewardAmount = _cumulativeRewardAmountArray[
						arrayLength.sub(1)
					].sub(rewardAmount);

					// set the previous endpoint cumulative reward amount
					_cumulativeRewardAmountArray[
						arrayLength.sub(1)
					] = _cumulativeRewardAmountArray[arrayLength.sub(2)].add(
						rewardAmount
					);
					// set the previous endpoint reward emission
					_rewardTokenEmissionArray[
						arrayLength.sub(1)
					] = rewardTokenEmission;
					// set the previous endpoint reward timestamp
					_rewardEmissionTimestampArray[arrayLength.sub(1)] = block
						.timestamp;

					// above logic is common for both conditions of rewardTokenEmission being zero or not
					// now if rewardEmission is not zero then create new array entry as endpoint, else
					// dump remaining reward amount to reward sink
					if (rewardTokenEmission > 0) {
						// set the new endpoint cumulative reward amount
						_cumulativeRewardAmount[holderContractAddress][
							rewardTokenContractAddress
						].push(
								_cumulativeRewardAmountArray[arrayLength.sub(1)]
									.add(remainingRewardAmount)
							);
						// set the new endpoint reward emission
						_rewardTokenEmission[holderContractAddress][
							rewardTokenContractAddress
						].push(0);
						// calculate the time interval across which emission will happen
						updatedTimestampRemainder = (
							(remainingRewardAmount.mul(_valueDivisor)).mod(
								rewardTokenEmission
							)
						).div(_valueDivisor);
						updatedTimestampRemainder = updatedTimestampRemainder >
							0
							? 1
							: 0;

						updatedTimestamp = (
							(remainingRewardAmount.mul(_valueDivisor)).div(
								rewardTokenEmission
							)
						).add(updatedTimestampRemainder).add(block.timestamp);

						// set the new endpoint reward timestamp
						_rewardEmissionTimestamp[holderContractAddress][
							rewardTokenContractAddress
						].push(updatedTimestamp);
					} else {
						_rewardSink[holderContractAddress][
							rewardTokenContractAddress
						] += remainingRewardAmount;
					}
				}
			} else {
				// if the timestamp endpoint is in the past or exact present
				// then check rewardSink and create two new entries in array
				rewardAmount = _rewardSink[holderContractAddress][
					rewardTokenContractAddress
				];
				if (rewardAmount == 0) revert("WR9");
				else {
					// clear the reward sink
					delete _rewardSink[holderContractAddress][
						rewardTokenContractAddress
					];
					// set the new penultimate cumulative reward amount
					_cumulativeRewardAmount[holderContractAddress][
						rewardTokenContractAddress
					].push(_cumulativeRewardAmountArray[arrayLength.sub(1)]);

					// set the new endpoint cumulative reward amount
					_cumulativeRewardAmount[holderContractAddress][
						rewardTokenContractAddress
					].push(
							_cumulativeRewardAmountArray[arrayLength.sub(1)]
								.add(rewardAmount)
						);

					// set the new penultimate reward emission
					_rewardTokenEmission[holderContractAddress][
						rewardTokenContractAddress
					].push(rewardTokenEmission);

					// set the new endpoint reward emission
					_rewardTokenEmission[holderContractAddress][
						rewardTokenContractAddress
					].push(0);

					// set the new penultimate reward timestamp
					_rewardEmissionTimestamp[holderContractAddress][
						rewardTokenContractAddress
					].push(block.timestamp);

					// calculate the time interval across which emission will happen
					updatedTimestampRemainder = (
						(rewardAmount.mul(_valueDivisor)).mod(
							rewardTokenEmission
						)
					).div(_valueDivisor);
					updatedTimestampRemainder = updatedTimestampRemainder > 0
						? 1
						: 0;

					updatedTimestamp = (
						(rewardAmount.mul(_valueDivisor)).div(
							rewardTokenEmission
						)
					).add(updatedTimestampRemainder).add(block.timestamp);

					// set the new endpoint reward timestamp
					_rewardEmissionTimestamp[holderContractAddress][
						rewardTokenContractAddress
					].push(updatedTimestamp);
				}
			}
		} else {
			// if the array has no entries, then create two new entries in the array
			// calculate the reward amount to be set in array
			if (rewardTokenEmission > 0) {
				rewardAmount = IERC20Upgradeable(rewardTokenContractAddress)
					.balanceOf(holderContractAddress);
				if (rewardAmount > 0) {
					// calculate the time interval across which emission will happen
					updatedTimestampRemainder = (
						(rewardAmount.mul(_valueDivisor)).mod(
							rewardTokenEmission
						)
					).div(_valueDivisor);
					updatedTimestampRemainder = updatedTimestampRemainder > 0
						? 1
						: 0;

					updatedTimestamp = (
						(rewardAmount.mul(_valueDivisor)).div(
							rewardTokenEmission
						)
					).add(updatedTimestampRemainder).add(block.timestamp);

					// set the new penultimate reward amount
					_cumulativeRewardAmount[holderContractAddress][
						rewardTokenContractAddress
					].push(0);
					// set the new penultimate reward emission
					_rewardTokenEmission[holderContractAddress][
						rewardTokenContractAddress
					].push(rewardTokenEmission);
					// set the new penultimate reward timestamp
					_rewardEmissionTimestamp[holderContractAddress][
						rewardTokenContractAddress
					].push(block.timestamp);

					// set the new endpoint reward amount
					_cumulativeRewardAmount[holderContractAddress][
						rewardTokenContractAddress
					].push(rewardAmount);
					// set the new endpoint reward emission
					_rewardTokenEmission[holderContractAddress][
						rewardTokenContractAddress
					].push(0);
					// set the new endpoint reward timestamp
					_rewardEmissionTimestamp[holderContractAddress][
						rewardTokenContractAddress
					].push(updatedTimestamp);
				} else {
					// if there is no reward balance then revert because one cannot
					// set an emission rate if there is no reward balance
					revert("WR10");
				}
			} else {
				// if new emission set is zero then revert because one cannot set a zero
				// emission rate the very first time as its already set as zero
				revert("WR11");
			}
		}

		emit SetRewardEmission(
			holderContractAddress,
			rewardTokenContractAddress,
			rewardTokenEmission,
			_valueDivisor,
			block.timestamp
		);
		success = true;
	}

	/*
	 * @dev get emission data
	 * @param holderContractAddress: holder contract address
	 * @param rewardTokenContractAddress: reward token contract address
	 */
	function getEmissionData(
		address holderContractAddress,
		address rewardTokenContractAddress
	)
		public
		view
		override
		returns (
			uint256[] memory cummulativeRewardAmount,
			uint256[] memory rewardTokenEmission,
			uint256[] memory rewardEmissionTimestamp
		)
	{
		return (
			_cumulativeRewardAmount[holderContractAddress][
				rewardTokenContractAddress
			],
			_rewardTokenEmission[holderContractAddress][
				rewardTokenContractAddress
			],
			_rewardEmissionTimestamp[holderContractAddress][
				rewardTokenContractAddress
			]
		);
	}

	/*
	 * @dev get timestamp data
	 * @param holderAddress: holder contract address
	 * @param lpTokenAddress: LP token contract address
	 * @param accountAddress: user address
	 * @param rewardTokenContractAddress: reward token contract address
	 */
	function getTimestampData(
		address holderAddress,
		address lpTokenAddress,
		address accountAddress,
		address rewardTokenContractAddress
	)
		public
		view
		returns (
			uint256[] memory lastLPTimeShareTimestampArray,
			uint256[] memory cumulativeNewSupplyLPTimeShare,
			uint256 rewardPoolUserTimestamp
		)
	{
		lastLPTimeShareTimestampArray = _lastLPTimeShareTimestampArray[
			lpTokenAddress
		];
		cumulativeNewSupplyLPTimeShare = _cumulativeNewSupplyLPTimeShare[
			lpTokenAddress
		];
		rewardPoolUserTimestamp = _rewardPoolUserTimestamp[holderAddress][
			rewardTokenContractAddress
		][accountAddress];
	}

	/**
	 * @dev Set 'contract address', called from constructor
	 *
	 * Emits a {SetStakeLPContract} event with '_contract' set to the stakeLP contract address.
	 *
	 */
	function setStakeLPContract(address stakeLPContract)
		public
		virtual
		override
	{
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "WR12");
		_stakeLPContract = stakeLPContract;
		emit SetStakeLPContract(stakeLPContract);
	}

	/*
	 * @dev set pool user timestamp
	 * @param holderContractAddress: holder contract address
	 * @param rewardTokenContractAddress: reward token contract address
	 * @param accountAddress:user address
	 * @param timestampValue: timestamp value
	 *
	 * Emits a {SetRewardPoolUserTimestamp} event
	 */
	function setRewardPoolUserTimestamp(
		address holderContractAddress,
		address rewardTokenContractAddress,
		address accountAddress,
		uint256 timestampValue
	) public override returns (bool success) {
		// require the message sender to be admin
		require(_msgSender() == _stakeLPContract, "WR13");
		// require the holder contract to be whitelisted for other reward tokens
		require(isHolderContractWhitelisted(holderContractAddress), "WR14");
		// require the reward token contract address be whitelisted for that holder contract
		require(
			_rewardTokenListIndex[holderContractAddress][
				rewardTokenContractAddress
			] != 0,
			"WR15"
		);
		_rewardPoolUserTimestamp[holderContractAddress][
			rewardTokenContractAddress
		][accountAddress] = timestampValue;

		emit SetRewardPoolUserTimestamp(
			holderContractAddress,
			rewardTokenContractAddress,
			accountAddress,
			timestampValue,
			block.timestamp
		);

		success = true;
	}

	/*
	 * @dev get reward pool user timestamp
	 * @param holderContractAddress: holder contract address
	 * @param rewardTokenContractAddress: reward token contract address
	 * @param accountAddress: user address
	 *
	 */
	function getRewardPoolUserTimestamp(
		address holderContractAddress,
		address rewardTokenContractAddress,
		address accountAddress
	) public view override returns (uint256 rewardPoolUserTimestamp) {
		if (
			holderContractAddress != address(0) &&
			rewardTokenContractAddress != address(0) &&
			accountAddress != address(0)
		) {
			rewardPoolUserTimestamp = _rewardPoolUserTimestamp[
				holderContractAddress
			][rewardTokenContractAddress][accountAddress];
		}
	}

	/*
	 * @dev set last LP timeshare timestamp
	 * @param lpToken: lp token contract address
	 * @param timestampValue: timestamp value
	 *
	 * Emits a {SetLastLPTimeShareTimestamp} event
	 */
	function setLastLPTimeShareTimestamp(
		address lpTokenAddress,
		uint256 timestampValue
	) public override returns (bool success) {
		// require the message sender to be admin
		require(_msgSender() == _stakeLPContract, "WR16");
		// require the arguments to be valid
		require(lpTokenAddress != address(0) && timestampValue != 0, "WR17");
		// update the _lastLPTimeShareTimestampArray only if the previous value doesnt match the current timestamp
		if (_lastLPTimeShareTimestampArray[lpTokenAddress].length == 0) {
			_lastLPTimeShareTimestampArray[lpTokenAddress].push(timestampValue);
		} else {
			if (
				!(_lastLPTimeShareTimestampArray[lpTokenAddress][
					(_lastLPTimeShareTimestampArray[lpTokenAddress].length).sub(
						1
					)
				] == timestampValue)
			) {
				_lastLPTimeShareTimestampArray[lpTokenAddress].push(
					timestampValue
				);
			}
		}

		emit SetLastLPTimeShareTimestamp(
			lpTokenAddress,
			timestampValue,
			block.timestamp
		);
		success = true;
	}

	/*
	 * @dev get last LP timeshare timestamp
	 * @param lpToken: lp token contract address
	 */
	function getLastLPTimeShareTimestamp(address lpTokenAddress)
		public
		view
		override
		returns (uint256 lastLPTimeShareTimestamp)
	{
		lastLPTimeShareTimestamp = _lastLPTimeShareTimestampArray[
			lpTokenAddress
		].length == 0
			? 0
			: _lastLPTimeShareTimestampArray[lpTokenAddress][
				(_lastLPTimeShareTimestampArray[lpTokenAddress].length).sub(1)
			];
	}

	/*
	 * @dev set last cummulative supply LP timeshare
	 * @param lpToken: lp token contract address
	 * @param newSupplyLPTimeShare: new supply timeshare
	 *
	 * Emits a {SetLastCummulativeSupplyLPTimeShare} event
	 *
	 */
	function setLastCummulativeSupplyLPTimeShare(
		address lpTokenAddress,
		uint256 newSupplyLPTimeShare
	) public override returns (bool success) {
		// require the message sender to be admin
		require(_msgSender() == _stakeLPContract, "WR18");
		// require the arguments to be valid
		require(lpTokenAddress != address(0), "WR19");

		uint256 lastCummulativeSupplyLPTimeShareIndex;
		if (_cumulativeNewSupplyLPTimeShare[lpTokenAddress].length == 0) {
			_cumulativeNewSupplyLPTimeShare[lpTokenAddress].push(
				newSupplyLPTimeShare
			);
		} else {
			lastCummulativeSupplyLPTimeShareIndex = (
				_lastLPTimeShareTimestampArray[lpTokenAddress].length
			).sub(1);
			// if the value in the last index of _lastLPTimeShareTimestampArray equals current timestamp
			// then only update the last index value of _cumulativeNewSupplyLPTimeShare else add new index value
			if (
				_lastLPTimeShareTimestampArray[lpTokenAddress][
					lastCummulativeSupplyLPTimeShareIndex
				] == block.timestamp
			) {
				_cumulativeNewSupplyLPTimeShare[lpTokenAddress][
					lastCummulativeSupplyLPTimeShareIndex
				] = _cumulativeNewSupplyLPTimeShare[lpTokenAddress][
					lastCummulativeSupplyLPTimeShareIndex
				].add(newSupplyLPTimeShare);
			} else {
				_cumulativeNewSupplyLPTimeShare[lpTokenAddress].push(
					_cumulativeNewSupplyLPTimeShare[lpTokenAddress][
						lastCummulativeSupplyLPTimeShareIndex
					].add(newSupplyLPTimeShare)
				);
			}
		}

		emit SetLastCummulativeSupplyLPTimeShare(
			lpTokenAddress,
			newSupplyLPTimeShare,
			block.timestamp
		);

		success = true;
	}

	/*
	 * @dev calculate updated supply LP timeshare
	  * @param holderAddress: holder contract address
	  * @param lpTokenAddress: LP token contract address
	  * @param rewardTokenAddress: reward token contract address
	  * @param accountAddress: user address
	  * @param newSupplyLPTimeShare: new supply LP timeshare
	 */
	function calculateUpdatedSupplyLPTimeShare(
		address holderAddress,
		address lpTokenAddress,
		address rewardTokenAddress,
		address accountAddress,
		uint256 newSupplyLPTimeShare
	) public view override returns (uint256 updatedSupplyLPTimeShare) {
		uint256 _startingCumulativeValue;
		uint256 _endingCumulativeValue;
		uint256 _rewardPoolUserTimestampLocal;
		uint256 _emissionEnd;
		uint256 _lpTimeShareTimestampEnd;

		_rewardPoolUserTimestampLocal = _rewardPoolUserTimestamp[holderAddress][
			rewardTokenAddress
		][accountAddress];

		// calculate the value of ending cumulative value. if the end of reward emission is smaller than last LP Supply
		// timeshare updation then call the getCumulativeSupplyValue function, else manually calculate.

		if (
			_rewardEmissionTimestamp[holderAddress][rewardTokenAddress]
				.length ==
			0 ||
			_lastLPTimeShareTimestampArray[lpTokenAddress].length == 0 ||
			_cumulativeNewSupplyLPTimeShare[lpTokenAddress].length == 0
		) {
			return updatedSupplyLPTimeShare;
		}

		_emissionEnd = _rewardEmissionTimestamp[holderAddress][
			rewardTokenAddress
		][
			(_rewardEmissionTimestamp[holderAddress][rewardTokenAddress].length)
				.sub(1)
		];
		_lpTimeShareTimestampEnd = _lastLPTimeShareTimestampArray[
			lpTokenAddress
		][(_lastLPTimeShareTimestampArray[lpTokenAddress].length).sub(1)];

		if (_emissionEnd <= _lpTimeShareTimestampEnd) {
			_endingCumulativeValue = getCumulativeSupplyValue(
				lpTokenAddress,
				_emissionEnd
			);
		} else {
			// if emissionEnd is smaller than or equal to current time then that the mulDiv ratio else
			// takt the whole newSupplyLPTimeShare and add to previous cumulative
			if (_emissionEnd <= block.timestamp) {
				_endingCumulativeValue = newSupplyLPTimeShare.mulDiv(
					_emissionEnd.sub(_lpTimeShareTimestampEnd),
					(block.timestamp).sub(_lpTimeShareTimestampEnd)
				);

				_endingCumulativeValue = _endingCumulativeValue.add(
					_cumulativeNewSupplyLPTimeShare[lpTokenAddress][
						_lpTimeShareTimestampEnd
					]
				);
			} else {
				_endingCumulativeValue = newSupplyLPTimeShare.add(
					_cumulativeNewSupplyLPTimeShare[lpTokenAddress][
						_lpTimeShareTimestampEnd
					]
				);
			}
		}

		_startingCumulativeValue = getCumulativeSupplyValue(
			lpTokenAddress,
			_rewardPoolUserTimestampLocal
		);

		updatedSupplyLPTimeShare = _endingCumulativeValue.sub(
			_startingCumulativeValue
		);
	}

	/*
	 * @dev calculate updated reward pool
	 * @param holderAddress: holder contract address
	 * @param rewardTokenAddress: reward token contract address
	 * @param accountAddress: user address
	 */
	function calculateUpdatedRewardPool(
		address holderAddress,
		address rewardTokenAddress,
		address accountAddress
	) public view override returns (uint256 updatedRewardPool) {
		uint256 _startingCumulativeValue;
		uint256 _endingCumulativeValue;
		uint256 _rewardEmissionTimestampLength;
		uint256 _rewardPoolUserTimestampLocal;

		_rewardEmissionTimestampLength = _rewardEmissionTimestamp[
			holderAddress
		][rewardTokenAddress].length;
		_rewardPoolUserTimestampLocal = _rewardPoolUserTimestamp[holderAddress][
			rewardTokenAddress
		][accountAddress];
		// if no emission array is found or current time has crossed the last entry of _rewardEmissionTimestamp
		// (reward endpoint timestamp) then set the updated reward pool to zero
		if (
			_rewardEmissionTimestampLength == 0 ||
			_rewardPoolUserTimestampLocal >
			_rewardEmissionTimestamp[holderAddress][rewardTokenAddress][
				_rewardEmissionTimestampLength.sub(1)
			]
		) {
			updatedRewardPool = 0;
		} else {
			// calculate reward pool balance as per user's _rewardPoolUserTimestamp and current time
			_startingCumulativeValue = getCumulativeRewardValue(
				holderAddress,
				rewardTokenAddress,
				_rewardPoolUserTimestampLocal
			);
			_endingCumulativeValue = getCumulativeRewardValue(
				holderAddress,
				rewardTokenAddress,
				block.timestamp
			);
			updatedRewardPool = _endingCumulativeValue.sub(
				_startingCumulativeValue
			);
		}
	}

	/*
	 * @dev calculate other pending rewards
	 * @param holderAddress: holder contract address
	 * @param lpTokenAddress: LP token contract address
	 * @param accountAddress: user address
	 * @param userLPTimeShare: user LP timeshare
	 * @param newSupplyLPTimeShare: new supply LP timeshare
	 */
	function calculateOtherPendingRewards(
		address holderAddress,
		address lpTokenAddress,
		address accountAddress,
		uint256 userLPTimeShare,
		uint256 newSupplyLPTimeShare
	)
		public
		view
		override
		returns (
			uint256[] memory otherRewardAmounts,
			address[] memory otherRewardTokens
		)
	{
		if (
			holderAddress == address(0) ||
			lpTokenAddress == address(0) ||
			accountAddress == address(0)
		) {
			return (otherRewardAmounts, otherRewardTokens);
		}

		uint256 _updatedRewardPool;
		uint256 _updatedSupplyLPTimeShare;
		uint256 i;

		otherRewardAmounts = new uint256[](
			_rewardTokenList[holderAddress].length
		);
		otherRewardTokens = new address[](
			_rewardTokenList[holderAddress].length
		);

		for (i = 0; i < _rewardTokenList[holderAddress].length; i = i.add(1)) {
			// allocate token contract address to otherRewardTokens
			otherRewardTokens[i] = _rewardTokenList[holderAddress][i];

			// -------------------------------------------------------------------------
			// -------------------------------------------------------------------------

			// calculate the updated reward pool to be considered for user's reward share calculation
			_updatedRewardPool = calculateUpdatedRewardPool(
				holderAddress,
				otherRewardTokens[i],
				accountAddress
			);

			// -------------------------------------------------------------------------
			// -------------------------------------------------------------------------

			// calculate the cummulative Supply LPTimeshare to be considered for user's reward share calculation
			_updatedSupplyLPTimeShare = calculateUpdatedSupplyLPTimeShare(
				holderAddress,
				lpTokenAddress,
				otherRewardTokens[i],
				accountAddress,
				newSupplyLPTimeShare
			);

			// -------------------------------------------------------------------------
			// -------------------------------------------------------------------------

			// calculate reward amount values for each reward token by calculating LPTimeShare of the updatedRewardPool
			if (_updatedSupplyLPTimeShare > 0) {
				// calculate user's reward for that particular reward token
				otherRewardAmounts[i] = _updatedRewardPool.mulDiv(
					userLPTimeShare,
					_updatedSupplyLPTimeShare
				);
			}
		}
	}

	/*
	 * @dev get cummulative reward value
	 * @param holderAddress: holder contract address
	 * @param rewardTokenContractAddress: reward token contract address
	 * @param rewardTimestamp: reward timestamp
	 */
	function getCumulativeRewardValue(
		address holderContractAddress,
		address rewardTokenContractAddress,
		uint256 rewardTimestamp
	) public view override returns (uint256 cumulativeRewardValue) {
		uint256[]
			storage _cumulativeRewardAmountArray = _cumulativeRewardAmount[
				holderContractAddress
			][rewardTokenContractAddress];
		uint256[]
			storage _rewardEmissionTimestampArray = _rewardEmissionTimestamp[
				holderContractAddress
			][rewardTokenContractAddress];
		uint256[] storage _rewardTokenEmissionArray = _rewardTokenEmission[
			holderContractAddress
		][rewardTokenContractAddress];

		if (
			holderContractAddress == address(0) ||
			rewardTokenContractAddress == address(0) ||
			_cumulativeRewardAmountArray.length == 0 ||
			_rewardEmissionTimestampArray.length == 0 ||
			_rewardTokenEmissionArray.length == 0
		) {
			return cumulativeRewardValue;
		}

		uint256 higherIndex;
		uint256 lowerIndex;
		uint256 midIndex;
		uint256 rewardAmount;
		uint256 timeInterval;

		higherIndex = (_rewardEmissionTimestampArray.length).sub(1);

		// if the timestamp marker is more than the endpoint reward timestamp, then return
		if (rewardTimestamp >= _rewardEmissionTimestampArray[higherIndex]) {
			cumulativeRewardValue = _cumulativeRewardAmountArray[higherIndex];
			return cumulativeRewardValue;
		}

		// if the timestamp marker value is zero then allocate timestamp at lowest index
		if (rewardTimestamp <= _rewardEmissionTimestampArray[lowerIndex]) {
			cumulativeRewardValue = _cumulativeRewardAmountArray[lowerIndex];
			return cumulativeRewardValue;
		}

		// find the index which is exact match for rewardTimestamp or comes closest to it
		// if the given timestamp doesnt match the first or last index of array,
		// traverse through array to get pin-point location's relative cumulative amount
		while (higherIndex.sub(lowerIndex) > 1) {
			midIndex = (higherIndex.add(lowerIndex)).div(2);
			if (rewardTimestamp == _rewardEmissionTimestampArray[midIndex]) {
				cumulativeRewardValue = _cumulativeRewardAmountArray[midIndex];
				break;
			} else if (
				rewardTimestamp < _rewardEmissionTimestampArray[midIndex]
			) {
				higherIndex = midIndex;
			} else {
				lowerIndex = midIndex;
			}
		}
		if (higherIndex.sub(lowerIndex) <= 1) {
			cumulativeRewardValue = _cumulativeRewardAmountArray[lowerIndex];
			timeInterval = rewardTimestamp.sub(
				_rewardEmissionTimestampArray[lowerIndex]
			);
			rewardAmount = timeInterval.mulDiv(
				_rewardTokenEmissionArray[lowerIndex],
				_valueDivisor
			);
			cumulativeRewardValue = cumulativeRewardValue.add(rewardAmount);
		}
		return cumulativeRewardValue;
	}

	/*
	 * @dev get cummulative supply value
	 * @param lpTokenAddress: LP token contract address
	 * @param lpSupplyTimestamp: LP supply timestamp
	 */
	function getCumulativeSupplyValue(
		address lpTokenAddress,
		uint256 lpSupplyTimestamp
	) public view override returns (uint256 cumulativeSupplyValue) {
		if (
			lpTokenAddress == address(0) ||
			_cumulativeNewSupplyLPTimeShare[lpTokenAddress].length == 0 ||
			_lastLPTimeShareTimestampArray[lpTokenAddress].length == 0
		) {
			return cumulativeSupplyValue;
		}

		uint256 higherIndex;
		uint256 lowerIndex;
		uint256 midIndex;
		uint256 timeInterval;
		uint256 timeDiff;
		uint256 supplyDiff;

		higherIndex = (_lastLPTimeShareTimestampArray[lpTokenAddress].length)
			.sub(1);

		// if the timestamp marker is more than the endpoint reward timestamp, then return
		if (
			lpSupplyTimestamp >=
			_lastLPTimeShareTimestampArray[lpTokenAddress][higherIndex]
		) {
			cumulativeSupplyValue = _cumulativeNewSupplyLPTimeShare[
				lpTokenAddress
			][higherIndex];
			return cumulativeSupplyValue;
		}

		// if the timestamp marker value is zero then allocate timestamp at lowest index
		if (
			lpSupplyTimestamp <=
			_lastLPTimeShareTimestampArray[lpTokenAddress][lowerIndex]
		) {
			cumulativeSupplyValue = _cumulativeNewSupplyLPTimeShare[
				lpTokenAddress
			][lowerIndex];
			return cumulativeSupplyValue;
		}

		// find the index which is exact match for lpSupplyTimestamp or comes closest to it
		// if the given timestamp doesnt match the first or last index of array,
		// traverse through array to get pin-point location's relative cumulative amount
		while (higherIndex.sub(lowerIndex) > 1) {
			midIndex = (higherIndex.add(lowerIndex)).div(2);
			if (
				lpSupplyTimestamp ==
				_lastLPTimeShareTimestampArray[lpTokenAddress][midIndex]
			) {
				cumulativeSupplyValue = _cumulativeNewSupplyLPTimeShare[
					lpTokenAddress
				][midIndex];
				break;
			} else if (
				lpSupplyTimestamp <
				_lastLPTimeShareTimestampArray[lpTokenAddress][midIndex]
			) {
				higherIndex = midIndex;
			} else {
				lowerIndex = midIndex;
			}
		}
		if (higherIndex.sub(lowerIndex) <= 1) {
			cumulativeSupplyValue = (
				_cumulativeNewSupplyLPTimeShare[lpTokenAddress][higherIndex]
			).sub(_cumulativeNewSupplyLPTimeShare[lpTokenAddress][lowerIndex]);
			timeDiff = lpSupplyTimestamp.sub(
				_lastLPTimeShareTimestampArray[lpTokenAddress][lowerIndex]
			);
			timeInterval = (
				_lastLPTimeShareTimestampArray[lpTokenAddress][higherIndex]
			).sub(_lastLPTimeShareTimestampArray[lpTokenAddress][lowerIndex]);
			supplyDiff = cumulativeSupplyValue.mulDiv(timeDiff, timeInterval);
			cumulativeSupplyValue = (
				_cumulativeNewSupplyLPTimeShare[lpTokenAddress][lowerIndex]
			).add(supplyDiff);
		}
		return cumulativeSupplyValue;
	}

	/*
	 * @dev check if holder contract address is whitelisted
	 * @param holderAddress: holder contract address
	 */
	function isHolderContractWhitelisted(address holderAddress)
		public
		view
		virtual
		override
		returns (bool result)
	{
		result = _holderContractList.contains(holderAddress);
		return result;
	}

	/*
	 * @dev set holder addresses for rewards
	 * @param holderContractAddress: holder contract address
	 * @param rewardTokenContractAddresses: reward token contract address in array
	 */
	function _setHolderAddressForRewards(
		address holderContractAddress,
		address[] memory rewardTokenContractAddresses
	) internal returns (bool success) {
		// add the Holder Contract address if it isn't already available
		if (!_holderContractList.contains(holderContractAddress)) {
			_holderContractList.add(holderContractAddress);
		}

		uint256 i;
		uint256 _rewardTokenContractAddressesLength = rewardTokenContractAddresses
				.length;
		for (i = 0; i < _rewardTokenContractAddressesLength; i = i.add(1)) {
			// add the Token Contract addresss to the reward tokens list for the Holder Contract
			if (rewardTokenContractAddresses[i] != address(0)) {
				// search if the reward token contract is already part of list
				if (
					_rewardTokenListIndex[holderContractAddress][
						rewardTokenContractAddresses[i]
					] == 0
				) {
					_rewardTokenList[holderContractAddress].push(
						rewardTokenContractAddresses[i]
					);
					_rewardTokenListIndex[holderContractAddress][
						rewardTokenContractAddresses[i]
					] = _rewardTokenList[holderContractAddress].length;
				}
			}
		}
		success = true;
		return success;
	}

	/*
	 * @dev set holder addresses for rewards
	 * @param holderContractAddresses: holder contract address in array
	 * @param rewardTokenContractAddresses: reward token contract address in array
	 *
	 * Emits a {SetHolderAddressesForRewards} event
	 *
	 */
	function setHolderAddressesForRewards(
		address[] memory holderContractAddresses,
		address[] memory rewardTokenContractAddresses
	) public override returns (bool success) {
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "WR20");
		uint256 _holderContractAddressesLength = holderContractAddresses.length;
		uint256 i;
		for (i = 0; i < _holderContractAddressesLength; i = i.add(1)) {
			require(holderContractAddresses[i] != address(0), "WR21");
			_setHolderAddressForRewards(
				holderContractAddresses[i],
				rewardTokenContractAddresses
			);
		}

		// emit an event capturing the action
		emit SetHolderAddressesForRewards(
			holderContractAddresses,
			rewardTokenContractAddresses,
			block.timestamp
		);

		success = true;
		return success;
	}

	/*
	 * @dev remove holder address for rewards
	 * @param holderContractAddress: holder contract address
	 */
	function _removeHolderAddressForRewards(address holderContractAddress)
		internal
		returns (bool success)
	{
		// delete holder contract from enumerable set
		_holderContractList.remove(holderContractAddress);
		// get the list of token contracts and remove the index values, and their emissions
		address[] memory _rewardTokenListLocal = _rewardTokenList[
			holderContractAddress
		];
		uint256 _rewardTokenListLength = _rewardTokenListLocal.length;
		uint256 i;
		for (i = 0; i < _rewardTokenListLength; i = i.add(1)) {
			delete _rewardTokenListIndex[holderContractAddress][
				_rewardTokenListLocal[i]
			];
		}
		// delete the list of token contract addresses
		delete _rewardTokenList[holderContractAddress];

		success = true;
		return success;
	}

	/*
	 * @dev remove holder addresses for rewards
	 * @param holderContractAddresses: holder contract address in array
	 *
	 * Emits a {RemoveHolderAddressesForRewards} event
	 */
	function removeHolderAddressesForRewards(
		address[] memory holderContractAddresses
	) public override returns (bool success) {
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "WR22");
		uint256 _holderContractAddressesLength = holderContractAddresses.length;
		uint256 i;
		for (i = 0; i < _holderContractAddressesLength; i = i.add(1)) {
			require(holderContractAddresses[i] != address(0), "WR23");
			_removeHolderAddressForRewards(holderContractAddresses[i]);
		}

		// emit an event capturing the action
		emit RemoveHolderAddressesForRewards(
			holderContractAddresses,
			block.timestamp
		);

		success = true;
		return success;
	}

	/*
	 * @dev remove token contract address for rewards
	 * @param holderContractAddress: holder contract address
	 * @param rewardTokenContractAddresses: reward token contract address in array
	 */
	function _removeTokenContractForRewards(
		address holderContractAddress,
		address[] memory rewardTokenContractAddresses
	) internal returns (bool success) {
		uint256 i;
		uint256 _rewardTokenContractAddressesLength = rewardTokenContractAddresses
				.length;
		for (i = 0; i < _rewardTokenContractAddressesLength; i = i.add(1)) {
			if (rewardTokenContractAddresses[i] != address(0)) {
				// remove the token address from the list
				uint256 rewardTokenListIndexLocal = _rewardTokenListIndex[
					holderContractAddress
				][rewardTokenContractAddresses[i]];
				if (rewardTokenListIndexLocal > 0) {
					if (
						rewardTokenListIndexLocal ==
						_rewardTokenList[holderContractAddress].length
					) {
						_rewardTokenList[holderContractAddress].pop();
					} else {
						_rewardTokenList[holderContractAddress][
							rewardTokenListIndexLocal.sub(1)
						] = _rewardTokenList[holderContractAddress][
							_rewardTokenList[holderContractAddress].length.sub(
								1
							)
						];
						_rewardTokenList[holderContractAddress].pop();
					}

					// delete the index value
					delete _rewardTokenListIndex[holderContractAddress][
						rewardTokenContractAddresses[i]
					];
				}
			}
		}

		success = true;
		return success;
	}

	/*
	 * @dev remove token contract address for rewards
	 * @param holderContractAddresses: holder contract address in array
	 * @param rewardTokenContractAddresses: reward token contract address in array
	 *
	 * Emits a {RemoveTokenContractsForRewards} event
	 *
	 */
	function removeTokenContractsForRewards(
		address[] memory holderContractAddresses,
		address[] memory rewardTokenContractAddresses
	) public override returns (bool success) {
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "WR24");
		uint256 _holderContractAddressesLength = holderContractAddresses.length;
		uint256 i;
		for (i = 0; i < _holderContractAddressesLength; i = i.add(1)) {
			require(holderContractAddresses[i] != address(0), "WR25");
			_removeTokenContractForRewards(
				holderContractAddresses[i],
				rewardTokenContractAddresses
			);
		}

		// emit an event capturing the action
		emit RemoveTokenContractsForRewards(
			holderContractAddresses,
			rewardTokenContractAddresses,
			block.timestamp
		);

		success = true;
		return success;
	}

	/**
	 * @dev Triggers stopped state.
	 *
	 * Requirements:
	 *
	 * - The contract must not be paused.
	 */
	function pause() public virtual override returns (bool success) {
		require(hasRole(PAUSER_ROLE, _msgSender()), "ST14");
		_pause();
		return true;
	}

	/**
	 * @dev Returns to normal state.
	 *
	 * Requirements:
	 *
	 * - The contract must be paused.
	 */
	function unpause() public virtual override returns (bool success) {
		require(hasRole(PAUSER_ROLE, _msgSender()), "ST15");
		_unpause();
		return true;
	}
}
