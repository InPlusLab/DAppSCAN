/*
 Copyright [2019] - [2021], PERSISTENCE TECHNOLOGIES PTE. LTD. and the pStake-smartContracts contributors
 SPDX-License-Identifier: Apache-2.0
*/

pragma solidity >=0.7.0;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/ISTokensV2.sol";
import "./interfaces/IWhitelistedPTokenEmission.sol";

contract WhitelistedPTokenEmission is
	IWhitelistedPTokenEmission,
	PausableUpgradeable,
	AccessControlUpgradeable
{
	using SafeMathUpgradeable for uint256;
	using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

	// constants defining access control ROLES
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
	// variable pertaining to contract upgrades versioning
	uint256 public _version;

	// -------------------------------------------------------------------------
	// -------------------------------------------------------------------------

	// ::HOLDER WHITELISTINGS FOR PTOKENS REWARD EMISSION::
	// list of whitelisted addresses for a particular holder contract
	mapping(address => address[]) public _holderWhitelists;
	// list of SToken addresses for a particular holder contract, for a particular whitelisted address
	mapping(address => mapping(address => address[]))
		public _whitelistedSTokenAddresses;
	// holder address for a particular whitelisted contract
	mapping(address => address) public _whitelistedAddressHolder;
	// lp token address for a particular holder address
	mapping(address => address) public _holderLPToken;
	// STokens pertaining to a holder address
	mapping(address => address[]) public _holderSTokens;

	// -------------------------------------------------------------------------
	// -------------------------------------------------------------------------

	/**
	 * @dev Constructor for initializing the SToken contract.
	 * @param pauserAddress - address of the pauser admin.
	 */
	function initialize(address pauserAddress) public virtual initializer {
		__AccessControl_init();
		__Pausable_init();
		_setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
		_setupRole(PAUSER_ROLE, pauserAddress);
		_version = 1;
	}

	/**
	 * @dev Calculate pending rewards for the provided 'address'. The rate is the moving reward rate.
	 * @param holderAddress: contract address
	 */
	function getHolderData(address holderAddress)
		public
		view
		virtual
		override
		returns (
			address[] memory whitelistedAddresses,
			address[] memory sTokenAddresses,
			address[] memory uTokenAddresses,
			address lpTokenAddress
		)
	{
		uint256 k;
		if (holderAddress != address(0)) {
			whitelistedAddresses = _holderWhitelists[holderAddress];
			lpTokenAddress = _holderLPToken[holderAddress];
			sTokenAddresses = _holderSTokens[holderAddress];
			uTokenAddresses = new address[](sTokenAddresses.length);
			for (k = 0; k < sTokenAddresses.length; k = k.add(1)) {
				uTokenAddresses[k] = ISTokensV2(sTokenAddresses[k])
					.getUTokenAddress();
			}
		}
	}

	/**
	 * @dev Check if contracts are whitelisted
	 * @param sTokenAddress: sToken contract address
	 * @param whitelistedAddresses: whitelisted contract address in array
	 */
	function areContractsWhitelisted(
		address sTokenAddress,
		address[] memory whitelistedAddresses
	) public view virtual override returns (bool[] memory areWhitelisted) {
		uint256 k;
		uint256 j;
		address[] memory sTokenAddressesLocal;
		address holderAddressLocal;
		bool isStokenMatch;
		areWhitelisted = new bool[](whitelistedAddresses.length);
		for (k = 0; k < whitelistedAddresses.length; k = k.add(1)) {
			holderAddressLocal = _whitelistedAddressHolder[
				whitelistedAddresses[k]
			];
			sTokenAddressesLocal = _whitelistedSTokenAddresses[
				holderAddressLocal
			][whitelistedAddresses[k]];
			isStokenMatch = false;
			for (j = 0; j < sTokenAddressesLocal.length; j = j.add(1)) {
				if (sTokenAddressesLocal[j] == sTokenAddress) {
					isStokenMatch = true;
					break;
				}
			}

			areWhitelisted[k] = isStokenMatch;
		}
	}

	/**
	 * @dev Calculate rewards for the holder 'address'.
	  * @param holderAddress: holder contract address
	 */
	function calculateAllHolderRewards(address holderAddress)
		public
		virtual
		override
		whenNotPaused
		returns (
			uint256[] memory holderRewards,
			address[] memory sTokenAddresses,
			address[] memory uTokenAddresses,
			address lpTokenAddress
		)
	{
		uint256 i;
		uint256 j;
		uint256 holderReward;
		uint256 rewardPool;
		bool[] memory areContractsWhitelistedBools;
		address[] memory whitelistedAddresses;

		(
			whitelistedAddresses,
			sTokenAddresses,
			uTokenAddresses,
			lpTokenAddress
		) = getHolderData(holderAddress);

		require(
			holderAddress != address(0) &&
				whitelistedAddresses.length > 0 &&
				uTokenAddresses.length > 0 &&
				sTokenAddresses.length > 0 &&
				lpTokenAddress != address(0),
			"WP1"
		);

		holderRewards = new uint256[](sTokenAddresses.length);
		// for each sTokenAddress, find all whitelistedAddresses and call calculatePendingHolderRewards,
		// add the results and store for each index
		for (i = 0; i < sTokenAddresses.length; i = i.add(1)) {
			rewardPool = 0;
			// list of bools which define if a particular whitelisted address conforms to the sTokenAddress
			areContractsWhitelistedBools = areContractsWhitelisted(
				sTokenAddresses[i],
				whitelistedAddresses
			);
			for (j = 0; j < whitelistedAddresses.length; j = j.add(1)) {
				// check if the sTokenAddress and whitelisted address pair is legitimate
				if (areContractsWhitelistedBools[j]) {
					(holderReward, , ) = ISTokensV2(sTokenAddresses[i])
						.calculateHolderRewards(whitelistedAddresses[j]);
					rewardPool = rewardPool.add(holderReward);
				}
			}
			holderRewards[i] = rewardPool;
		}

		emit CalculateAllHolderRewards(
			holderAddress,
			holderRewards,
			block.timestamp
		);
	}

	/**
	 * @dev Calculate pending rewards for the holder 'address'
	  * @param holderAddress: holder contract address
	 */
	function calculateAllPendingHolderRewards(address holderAddress)
		public
		view
		override
		returns (
			uint256[] memory holderRewards,
			address[] memory sTokenAddresses,
			address[] memory uTokenAddresses,
			address lpTokenAddress
		)
	{
		uint256 i;
		uint256 j;
		uint256 holderReward;
		uint256 rewardPool;
		bool[] memory areContractsWhitelistedBools;
		address[] memory whitelistedAddresses;

		(
			whitelistedAddresses,
			sTokenAddresses,
			uTokenAddresses,
			lpTokenAddress
		) = getHolderData(holderAddress);

		if (
			holderAddress == address(0) ||
			lpTokenAddress == address(0) ||
			whitelistedAddresses.length == 0 ||
			uTokenAddresses.length == 0 ||
			sTokenAddresses.length == 0
		) {
			return (holderRewards, sTokenAddresses, uTokenAddresses, lpTokenAddress);
		}

		holderRewards = new uint256[](sTokenAddresses.length);
		// for each sTokenAddress, find all whitelistedAddresses and call calculatePendingHolderRewards,
		// add the results and store for each index
		for (i = 0; i < sTokenAddresses.length; i = i.add(1)) {
			rewardPool = 0;
			// list of bools which define if a particular whitelisted address conforms to the sTokenAddress
			areContractsWhitelistedBools = areContractsWhitelisted(
				sTokenAddresses[i],
				whitelistedAddresses
			);
			for (j = 0; j < whitelistedAddresses.length; j = j.add(1)) {
				// check if the sTokenAddress and whitelisted address pair is legitimate
				if (areContractsWhitelistedBools[j]) {
					(holderReward, , ) = ISTokensV2(sTokenAddresses[i])
						.calculatePendingHolderRewards(whitelistedAddresses[j]);
					rewardPool = rewardPool.add(holderReward);
				}
			}
			holderRewards[i] = rewardPool;
		}
	}

	/*
	 * @dev Set 'whitelisted address', performed by admin only
	 * @param whitelistedAddress: contract address of the whitelisted party
	 * @param sTokenAddresses: sToken contract address in array
	 * @param holderContractAddress: holder contract address
	 * @param lpContractAddress: LP token contract address
	 *
	 * Emits a {setWhitelistedAddress} event
	 *
	 */
	function setWhitelistedAddress(
		address whitelistedAddress,
		address[] memory sTokenAddresses,
		address holderContractAddress,
		address lpContractAddress
	) public virtual override returns (bool success) {
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "WP2");
		// lpTokenERC20ContractAddress or sTokenReserveContractAddress can be address(0) but not whitelistedAddress
		// have set holderContract also as non-zero, can allow lpContractAddress to be zero for control
		require(
			whitelistedAddress != address(0) &&
				holderContractAddress != address(0) &&
				sTokenAddresses.length != 0,
			"WP3"
		);

		bool whitelistedAddressExists;
		uint256 j;
		uint256 i;

		// ADD TO _holderWhitelists make sure the same whitelisted address is not added before if so revert
		// to add the same whitelisted address, first remove it, then add again
		// add to _holderWhitelists
		for (
			j = 0;
			j < _holderWhitelists[holderContractAddress].length;
			j = j.add(1)
		) {
			if (
				_holderWhitelists[holderContractAddress][j] ==
				whitelistedAddress
			) {
				whitelistedAddressExists = true;
				break;
			}
		}

		// if whitelisted contract doesnt already exist then include it in the array else revert
		if (!whitelistedAddressExists) {
			// add the whitelistedAddress to the _holderWhitelists array
			_holderWhitelists[holderContractAddress].push(whitelistedAddress);
		} else {
			revert("WP4");
		}

		// ADD TO _holderWhitelists AND _whitelistedSTokenAddresses AND _whitelistedAddressHolder AND _holderLPToken
		_whitelistedAddressHolder[whitelistedAddress] = holderContractAddress;
		_holderLPToken[holderContractAddress] = lpContractAddress;

		// add SToken addresses uniquely to _holderSTokens
		for (i = 0; i < sTokenAddresses.length; i = i.add(1)) {
			// ADD TO _whitelistedSTokenAddresses
			// check if sTokenAddress already exists
			// check if all the sTokenAddresses provided are non zero
			require(sTokenAddresses[i] != address(0), "WP5");
			_whitelistedSTokenAddresses[holderContractAddress][
				whitelistedAddress
			].push(sTokenAddresses[i]);

			// SET WHITELISTING IN STOKEN CONTRACTS
			// for each sTokenAddress, set the whiteliste data
			ISTokensV2(sTokenAddresses[j]).setWhitelistedAddress(
				whitelistedAddress,
				holderContractAddress,
				lpContractAddress
			);
			// ADD TO _holderWhitelists
			for (
				j = 0;
				j < _holderSTokens[holderContractAddress].length;
				j = j.add(1)
			) {
				if (
					sTokenAddresses[i] ==
					_holderSTokens[holderContractAddress][j]
				) {
					break;
				}
			}
			if (j == _holderSTokens[holderContractAddress].length) {
				_holderSTokens[holderContractAddress].push(sTokenAddresses[i]);
			}
		}

		// emit event
		emit SetWhitelistedAddress(
			whitelistedAddress,
			_whitelistedSTokenAddresses[holderContractAddress][
				whitelistedAddress
			],
			holderContractAddress,
			lpContractAddress,
			block.timestamp
		);

		success = true;
		return success;
	}

	/*
	 * @dev remove 'whitelisted address', performed by admin only
	 * @param whitelistedAddress: contract address of the whitelisted party
	 *
	 * Emits a {RemoveWhitelistedAddress} event
	 *
	 */
	function removeWhitelistedAddress(address whitelistedAddress)
		public
		virtual
		override
		returns (bool success)
	{
		require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "WP6");
		require(whitelistedAddress != address(0), "WP7");

		// REMOVE WHITELISTING FROM _holderWhitelists AND _whitelistedSTokenAddresses AND _whitelistedAddressHolder AND _holderLPToken
		// get the holder address from _whitelistedAddressHolder
		address holderAddressLocal = _whitelistedAddressHolder[
			whitelistedAddress
		];

		// emit event
		emit RemoveWhitelistedAddress(
			whitelistedAddress,
			_whitelistedSTokenAddresses[holderAddressLocal][whitelistedAddress],
			_whitelistedAddressHolder[whitelistedAddress],
			block.timestamp
		);

		// REMOVE FROM STOKEN CONTRACTS
		// for each SToken, call the remove whitelist function of that SToken
		uint256 j;
		for (
			j = 0;
			j <
			_whitelistedSTokenAddresses[holderAddressLocal][whitelistedAddress]
				.length;
			j = j.add(1)
		) {
			ISTokensV2(
				_whitelistedSTokenAddresses[holderAddressLocal][
					whitelistedAddress
				][j]
			).removeWhitelistedAddress(whitelistedAddress);
		}

		// REMOVE FROM _whitelistedAddressHolder and _whitelistedSTokenAddresses
		delete _whitelistedAddressHolder[whitelistedAddress];
		delete _whitelistedSTokenAddresses[holderAddressLocal][
			whitelistedAddress
		];

		// REMOVE FROM _holderWhitelists
		// check if the whitelisted address exists is the _holderWhitelists array
		bool whitelistedAddressExists;
		for (
			j = 0;
			j < _holderWhitelists[holderAddressLocal].length;
			j = j.add(1)
		) {
			if (
				_holderWhitelists[holderAddressLocal][j] == whitelistedAddress
			) {
				whitelistedAddressExists = true;
				break;
			}
		}
		// if whitelisted contract exists in the_holderWhitelists array then
		// remove the whitelisted address from the array of _holderWhitelists
		if (whitelistedAddressExists) {
			if (j == _holderWhitelists[holderAddressLocal].length.sub(1)) {
				_holderWhitelists[holderAddressLocal].pop();
			} else {
				_holderWhitelists[holderAddressLocal][j] = _holderWhitelists[
					holderAddressLocal
				][_holderWhitelists[holderAddressLocal].length.sub(1)];
				_holderWhitelists[holderAddressLocal].pop();
			}
			// if all the whitelisted addresses have been removed, then delete the lpToken associated with the holder address
			if (_holderWhitelists[holderAddressLocal].length == 0) {
				delete _holderLPToken[holderAddressLocal];
				delete _holderSTokens[holderAddressLocal];
			}
		}

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
		require(hasRole(PAUSER_ROLE, _msgSender()), "WP8");
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
		require(hasRole(PAUSER_ROLE, _msgSender()), "WP9");
		_unpause();
		return true;
	}
}
