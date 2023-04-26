pragma solidity ^0.6.2;

import "./IPeakDeFi.sol";


contract PeakTokenSwap {
    address public wallet;
	IPeakDeFi public fromERC20;
	IPeakDeFi public toERC20;

	event TokenSwap(
		address indexed owner,
		address fromERC20,
		address toERC20,
		uint256 balance
	);

	constructor(
        address _wallet,
		address _fromERC20,
		address _toERC20
	)
		public
	{
        wallet = _wallet;
		fromERC20 = IPeakDeFi(_fromERC20);
		toERC20 = IPeakDeFi(_toERC20);
	}

	function swap(uint256 swapAmount) external {
        // Validate balances and allowances before transfer
		require(swapAmount > 0, "swap: No tokens to transfer!");

		// Send and lock the old tokens to this contract
        uint256 availableAllowance = toERC20.allowance(wallet, address(this));
		require(availableAllowance >= swapAmount, "swap: Not enough new tokens to transfer!");

        // Receive and burn old tokens
		require(fromERC20.transferFrom(msg.sender, address(this), swapAmount));
		fromERC20.burn(swapAmount);

        // Transfer new tokens to sender
		require(toERC20.transferFrom(wallet, msg.sender, swapAmount));

		emit TokenSwap(msg.sender, address(fromERC20), address(toERC20), swapAmount);
	}
}