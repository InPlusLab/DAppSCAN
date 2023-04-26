// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
pragma abicoder v2;
 
import { IforbitspaceX } from "./interfaces/IforbitspaceX.sol";
import { Payment, SafeMath, Address } from "./libraries/Payment.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract forbitspaceX is IforbitspaceX, Payment, ReentrancyGuard {
	using SafeMath for uint;
	using Address for address;

	constructor(address _WBNB, address _admin) Payment(_WBNB, _admin) {}

	function aggregate(
		address tokenIn,
		address tokenOut,
		uint amountInTotal,
		address recipient,
		SwapParam[] calldata params
	) public payable override nonReentrant returns (uint amountInActual, uint amountOutActual) {
		// check invalid tokens address
		require(!(tokenIn == tokenOut), "I_T_A");
		require(!(tokenIn == BNB_ADDRESS && tokenOut == WBNB_ADDRESS), "I_T_A");
		require(!(tokenIn == WBNB_ADDRESS && tokenOut == BNB_ADDRESS), "I_T_A");

		// check invalid value
		if (tokenIn == BNB_ADDRESS) {
			amountInTotal = msg.value;
		} else {
			require(msg.value == 0, "I_V");
		}
		require(amountInTotal > 0, "I_V");

		// receive tokens
		pay(address(this), tokenIn, amountInTotal);

		// amountAcutual before
		uint amountInBefore = balanceOf(tokenIn);
		amountOutActual = balanceOf(tokenOut);

		// call swap on multi dexs
		_swap(params);

		// amountAcutual after
		amountInActual = amountInBefore.sub(balanceOf(tokenIn));
		amountOutActual = balanceOf(tokenOut).sub(amountOutActual);

		require((amountInActual > 0) && (amountOutActual > 0), "I_A_T_A"); // incorrect actual total amounts

		// refund tokens
		pay(_msgSender(), tokenIn, amountInBefore.sub(amountInActual, "N_E_T")); // not enough tokens
		pay(recipient, tokenOut, amountOutActual.mul(9995).div(10000)); // 0.05% fee

		// sweep tokens for owner
		collectTokens(tokenIn);
		collectTokens(tokenOut);
	}

	function _swap(SwapParam[] calldata params) private {
		for (uint i = 0; i < params.length; i++) {
			SwapParam calldata p = params[i];
			(
				address exchangeTarget,
				address addressToApprove,
				address tokenIn,
				address tokenOut,
				bytes calldata swapData
			) = (p.exchangeTarget, p.addressToApprove, p.tokenIn, p.tokenOut, p.swapData);

			// approve(addressToApprove, tokenIn, type(uint).max);
			approve(addressToApprove, tokenIn, balanceOf(tokenIn));

			uint amountInActual = balanceOf(tokenIn);
			uint amountOutActual = balanceOf(tokenOut);

			exchangeTarget.functionCall(swapData, "L_C_F"); // low-level call failed

			// amountInActual = amountInActual.sub(balanceOf(tokenIn));
			// amountOutActual = balanceOf(tokenOut).sub(amountOutActual);

			bool success = ((balanceOf(tokenIn) < amountInActual) && (balanceOf(tokenOut) > amountOutActual));

			require(success, "I_A_A"); // incorrect actual amounts
		}
	}
}
