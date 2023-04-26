// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "../TokenSale.sol";

contract TokenSaleMock is TokenSale {
	constructor(
		IERC20 _saleToken,
		uint256 _price,
		uint256 _maxBuyAmount,
		uint256 _cap,
		uint256 _releaseTime,
		uint256 _unlockTime
	)
		TokenSale(
			_saleToken,
			_price,
			_maxBuyAmount,
			_cap,
			_releaseTime,
			_unlockTime
		)
	{}

	function getAmountsOut(uint256 amount) internal pure returns (uint256) {
		return amount;
	}

	function setUSDCAddress(address _newAdd) public onlyOwner {
		usdcAddress = _newAdd;
	}

	function buyByUSDC(uint256 _buyAmount) external payable override {
		require(
			tokensSold + _buyAmount <= cap,
			"Cannot buy that exceeds the cap"
		);
		PurchasedAmount storage allocation = purchasedAmount[msg.sender];
		uint256 amount = getAmountsOut(price * _buyAmount);
		require(
			IERC20(usdcAddress).transferFrom(msg.sender, address(this), amount),
			"TF: Check allowance"
		);

		allocation.usdcAmount += (_buyAmount * multiplier) / 100;

		LockedAmount storage allocationLocked = lockedAmount[msg.sender];

		allocationLocked.usdcAmount += (_buyAmount * (100 - multiplier)) / 100;
		allocation.usdcInvested += amount;

		require(
			allocation.nativeAmount +
				allocation.usdcAmount +
				allocationLocked.nativeAmount +
				allocationLocked.usdcAmount <=
				maxBuyAmount
		);

		tokensSold += _buyAmount;

		emit Sold(msg.sender, _buyAmount, false);
	}
}
