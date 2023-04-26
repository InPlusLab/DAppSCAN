// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.2;

abstract contract ApeAllowanceModule {

	struct Allowance {
		uint256 maxAmount;
		uint256 cooldownInterval;
	}

	struct CurrentAllowance {
		uint256 debt;
		uint256 intervalStart;
		uint256 epochs;
	}

	// vault => circle => token => allowance
	mapping(address => mapping(bytes32 => mapping(address => Allowance))) public allowances;
	mapping(address => mapping(bytes32 => mapping(address => CurrentAllowance))) public currentAllowances;

	event AllowanceUpdated(address vault, bytes32 circle, address token, uint256 amount, uint256 interval);


	/**  
	 * @notice
	 * Used to set an allowance of a circle from an ape vault.
	 * Setting _epochs at 0 with a non-zero _amount entitles the circle to one epoch of funds
	 * @param _circle Circle ID receiving the allowance
	 * @param _token Address of token to allocate
	 * @param _amount Amount to take out at most
	 * @param _cooldownInterval Duration of an epoch in seconds
	 * @param _epochs Amount of epochs to fund. Expected_funded_epochs = _epochs + 1
	 * @param _intervalStart Unix timestamp fromw hich epoch starts (block.timestamp if 0)
	 */
	function setAllowance(
		bytes32 _circle,
		address _token,
		uint256 _amount,
		uint256 _cooldownInterval,
		uint256 _epochs,
		uint256 _intervalStart
		) external {
		uint256 _now = block.timestamp;
		if (_intervalStart == 0)
			_intervalStart = _now;
		require(_intervalStart >= _now, "Interval start in the past");
		allowances[msg.sender][_circle][_token] = Allowance({
			maxAmount: _amount,
			cooldownInterval: _cooldownInterval
		});
		currentAllowances[msg.sender][_circle][_token] = CurrentAllowance({
			debt: 0,
			intervalStart: _intervalStart,
			epochs: _epochs
		});
		emit AllowanceUpdated(msg.sender, _circle, _token, _amount, _cooldownInterval);
	}

	/**  
	 * @notice
	 * Used to check and update if a circle can take funds out of an ape vault
	 * @param _vault Address of vault to take funds from
	 * @param _circle Circle ID querying the funds
	 * @param _token Address of token to take out
	 * @param _amount Amount to take out
	 */
	function _isTapAllowed(
		address _vault,
		bytes32 _circle,
		address _token,
		uint256 _amount
		) internal {
		Allowance memory allowance = allowances[_vault][_circle][_token];
		CurrentAllowance storage currentAllowance = currentAllowances[_vault][_circle][_token];
		require(_amount <= allowance.maxAmount, "Amount tapped exceed max allowance");
		require(block.timestamp >= currentAllowance.intervalStart, "Epoch has not started");

		if (currentAllowance.debt + _amount > allowance.maxAmount)
			_updateInterval(currentAllowance, allowance);
		currentAllowance.debt += _amount;
	}

	function _updateInterval(CurrentAllowance storage _currentAllowance, Allowance memory _allowance) internal {
		uint256 elapsedTime = block.timestamp - _currentAllowance.intervalStart;
		require(elapsedTime > _allowance.cooldownInterval, "Cooldown interval not finished");
		require(_currentAllowance.epochs > 0, "Circle cannot tap anymore");
		_currentAllowance.debt = 0;
		_currentAllowance.intervalStart = block.timestamp;
		_currentAllowance.epochs--;
	}
}