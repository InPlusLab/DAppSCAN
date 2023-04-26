// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { WETH } from "../interop/WrappedEther.sol";

import { $ } from "../network/$.sol";

/**
 * @dev This library abstracts Wrapped Ether operations.
 */
library Wrapping
{
	/**
	 * @dev Sends some ETH to the Wrapped Ether contract in exchange for WETH.
	 * @param _amount The amount of ETH to be wrapped in WETH.
	 * @return _success A boolean indicating whether or not the operation suceeded.
	 */
	function _wrap(uint256 _amount) internal returns (bool _success)
	{
		try WETH($.WETH).deposit{value: _amount}() {
			return true;
		} catch (bytes memory /* _data */) {
			return false;
		}
	}

	/**
	 * @dev Receives some ETH from the Wrapped Ether contract in exchange for WETH.
	 *      Note that the contract using this library function must declare a
	 *      payable receive/fallback function.
	 * @param _amount The amount of ETH to be wrapped in WETH.
	 * @return _success A boolean indicating whether or not the operation suceeded.
	 */
	function _unwrap(uint256 _amount) internal returns (bool _success)
	{
		try WETH($.WETH).withdraw(_amount) {
			return true;
		} catch (bytes memory /* _data */) {
			return false;
		}
	}

	/**
	 * @dev Sends some ETH to the Wrapped Ether contract in exchange for WETH.
	 *      This operation will revert if it does not succeed.
	 * @param _amount The amount of ETH to be wrapped in WETH.
	 */
	function _safeWrap(uint256 _amount) internal
	{
		require(_wrap(_amount), "wrap failed");
	}

	/**
	 * @dev Receives some ETH from the Wrapped Ether contract in exchange for WETH.
	 *      This operation will revert if it does not succeed. Note that
	 *      the contract using this library function must declare a payable
	 *      receive/fallback function.
	 * @param _amount The amount of ETH to be wrapped in WETH.
	 */
	function _safeUnwrap(uint256 _amount) internal
	{
		require(_unwrap(_amount), "unwrap failed");
	}
}
