// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
pragma abicoder v2;

import { IPayment } from "./IPayment.sol";

interface IforbitspaceX is IPayment {
	struct SwapParam {
		address addressToApprove;
		address exchangeTarget;
		address tokenIn; // tokenFrom
		address tokenOut; // tokenTo
		bytes swapData;
	}

	function aggregate(
		address tokenIn,
		address tokenOut,
		uint amountInTotal,
		address recipient,
		SwapParam[] calldata params
	) external payable returns (uint amountInAcutual, uint amountOutAcutual);
}
