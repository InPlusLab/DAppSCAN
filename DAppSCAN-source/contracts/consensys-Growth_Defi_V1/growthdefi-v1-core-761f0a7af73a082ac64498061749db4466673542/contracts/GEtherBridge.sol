// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { GToken } from "./GToken.sol";
import { GCToken } from "./GCToken.sol";
import { G } from "./G.sol";

import { $ } from "./network/$.sol";

/**
 * @dev This contract serves as a useful bridge between ETH and the WETH
 *      ERC-20 based gTokens. It accepts deposits/withdrawals in ETH performing
 *      the wrapping/unwrapping behind the scenes.
 */
contract GEtherBridge
{
	/**
	 * @notice Accepts a deposit to the gToken using ETH. The gToken must
	 *         have WETH as its reserveToken. This is a payable method and
	 *         expects ETH to be sent; which in turn will be converted into
	 *         shares. See GToken.sol and GTokenBase.sol for further
	 *         documentation.
	 * @param _growthToken The WETH based gToken.
	 */
	function deposit(address _growthToken) public payable
	{
		address _from = msg.sender;
		uint256 _cost = msg.value;
		address _reserveToken = GToken(_growthToken).reserveToken();
		require(_reserveToken == $.WETH, "ETH operation not supported by token");
		G.safeWrap(_cost);
		G.approveFunds(_reserveToken, _growthToken, _cost);
		GToken(_growthToken).deposit(_cost);
		uint256 _netShares = G.getBalance(_growthToken);
		G.pushFunds(_growthToken, _from, _netShares);
	}

	/**
	 * @notice Accepts a withdrawal to the gToken using ETH. The gToken must
	 *         have WETH as its reserveToken. This method will redeem the
	 *         sender's required balance in shares; which in turn will receive
	 *         ETH. See GToken.sol and GTokenBase.sol for further documentation.
	 * @param _growthToken The WETH based gToken.
	 * @param _grossShares The number of shares to be redeemed.
	 */
	function withdraw(address _growthToken, uint256 _grossShares) public
	{
		address payable _from = msg.sender;
		address _reserveToken = GToken(_growthToken).reserveToken();
		require(_reserveToken == $.WETH, "ETH operation not supported by token");
		G.pullFunds(_reserveToken, _from, _grossShares);
		GToken(_growthToken).withdraw(_grossShares);
		uint256 _cost = G.getBalance(_reserveToken);
		G.safeUnwrap(_cost);
		_from.transfer(_cost);
	}

	/**
	 * @notice Accepts a deposit to the gcToken using ETH. The gcToken must
	 *         have WETH as its underlyingToken. This is a payable method and
	 *         expects ETH to be sent; which in turn will be converted into
	 *         shares. See GCToken.sol and GCTokenBase.sol for further
	 *         documentation.
	 * @param _growthToken The WETH based gcToken (e.g. gcETH).
	 */
	function depositUnderlying(address _growthToken) public payable
	{
		address _from = msg.sender;
		uint256 _underlyingCost = msg.value;
		address _underlyingToken = GCToken(_growthToken).underlyingToken();
		require(_underlyingToken == $.WETH, "ETH operation not supported by token");
		G.safeWrap(_underlyingCost);
		G.approveFunds(_underlyingToken, _growthToken, _underlyingCost);
		GCToken(_growthToken).depositUnderlying(_underlyingCost);
		uint256 _netShares = G.getBalance(_growthToken);
		G.pushFunds(_growthToken, _from, _netShares);
	}

	/**
	 * @notice Accepts a withdrawal to the gcToken using ETH. The gcToken must
	 *         have WETH as its underlyingToken. This method will redeem the
	 *         sender's required balance in shares; which in turn will receive
	 *         ETH. See GCToken.sol and GCTokenBase.sol for further documentation.
	 * @param _growthToken The WETH based gcToken (e.g. gcETH).
	 * @param _grossShares The number of shares to be redeemed.
	 */
	function withdrawUnderlying(address _growthToken, uint256 _grossShares) public
	{
		address payable _from = msg.sender;
		address _underlyingToken = GCToken(_growthToken).underlyingToken();
		require(_underlyingToken == $.WETH, "ETH operation not supported by token");
		G.pullFunds(_growthToken, _from, _grossShares);
		GCToken(_growthToken).withdrawUnderlying(_grossShares);
		uint256 _underlyingCost = G.getBalance(_underlyingToken);
		G.safeUnwrap(_underlyingCost);
		_from.transfer(_underlyingCost);
	}

	receive() external payable {} // not to be used directly
}
