// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.2;

import "./TimeLock.sol";

contract FeeRegistry is TimeLock(0){
	uint256 private constant _staticFee = 100; // 100 | MAX = 10000
	bool public on;

	function activateFee() external itself {
		on = true;
	}

	function shutdownFee() external itself {
		on = false;
	}

	function staticFee() external view returns(uint256) {
		if (!on)
			return 0;
		return _staticFee;
	}

	function getVariableFee(uint256 _yield, uint256 _tapTotal) external returns(uint256 variableFee) {
		if (!on)
			return 0;
		uint256 yieldRatio = _yield * 1000 / _tapTotal;
		uint256 baseFee = 100;
		if (yieldRatio >= 900)
			variableFee = baseFee;        // 1%     @ 90% profit
		else if (yieldRatio >= 800)
			variableFee = baseFee + 25;   // 1.25%  @ 80% profit
		else if (yieldRatio >= 700)
			variableFee = baseFee + 50;   // 1.50%  @ 70% profit
		else if (yieldRatio >= 600)
			variableFee = baseFee + 75;   // 1.75%  @ 60% profit
		else if (yieldRatio >= 500)
			variableFee = baseFee + 100;  // 2.00%  @ 80% profit
		else if (yieldRatio >= 400)
			variableFee = baseFee + 125;  // 2.25%  @ 80% profit
		else if (yieldRatio >= 300)
			variableFee = baseFee + 150;  // 2.50%  @ 80% profit
		else if (yieldRatio >= 200)
			variableFee = baseFee + 175;  // 2.75%  @ 80% profit
		else if (yieldRatio >= 100)
			variableFee = baseFee + 200;  // 3.00%  @ 80% profit
		else
			variableFee = baseFee + 250;  // 3.50%  @ 0% profit
	}
}
