// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/EnumerableSet.sol";

/**
 * @notice Implements a whitelist-based policy for accessing publicly available
 *         functions of subcontracts. Enforces that a public function can only
 *         be called by an External Owned Account (EOA) or a contract previously
 *         whitelisted.
 */
abstract contract WhitelistGuard is Ownable
{
	using EnumerableSet for EnumerableSet.AddressSet;

	EnumerableSet.AddressSet private whitelist;
	bool private enabled = true;

	/// @dev restricts function call to be EOA or whitelist
	modifier onlyEOAorWhitelist()
	{
		if (enabled) {
			address _from = _msgSender();
			require(tx.origin == _from || whitelist.contains(_from), "access denied");
		}
		_;
	}

	/// @dev restricts function call to whitelist
	modifier onlyWhitelist()
	{
		if (enabled) {
			address _from = _msgSender();
			require(whitelist.contains(_from), "access denied");
		}
		_;
	}

	/**
	 * @notice Adds an address to the access policy whitelist.
	 *         This is a priviledged function.
	 * @param _address The address to be added to the whitelist.
	 */
	function addToWhitelist(address _address) external onlyOwner
	{
		require(whitelist.add(_address), "already listed");
	}

	/**
	 * @notice Removes an address to the access policy whitelist.
	 *         This is a priviledged function.
	 * @param _address The address to be removed to the whitelist.
	 */
	function removeFromWhitelist(address _address) external onlyOwner
	{
		require(whitelist.remove(_address), "not listed");
	}

	/**
	 * @notice Enables/disables the whitelist access policy.
	 *         This is a priviledged function.
	 * @param _enabled Flag indicating whether the whitelist should be
	 *                 enabled or not.
	 */
	function setWhitelistEnabled(bool _enabled) external onlyOwner
	{
		enabled = _enabled;
	}
}
