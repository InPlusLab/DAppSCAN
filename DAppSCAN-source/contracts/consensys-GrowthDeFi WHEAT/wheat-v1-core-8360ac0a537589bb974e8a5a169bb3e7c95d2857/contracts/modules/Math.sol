// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

/**
 * @dev This library implements auxiliary math definitions.
 */
library Math
{
	function _min(uint256 _amount1, uint256 _amount2) internal pure returns (uint256 _minAmount)
	{
		return _amount1 < _amount2 ? _amount1 : _amount2;
	}

	function _max(uint256 _amount1, uint256 _amount2) internal pure returns (uint256 _maxAmount)
	{
		return _amount1 > _amount2 ? _amount1 : _amount2;
	}

	function _sqrt(uint256 _y) internal pure returns (uint256 _z)
	{
		if (_y > 3) {
			_z = _y;
			uint256 _x = _y / 2 + 1;
			while (_x < _z) {
				_z = _x;
				_x = (_y / _x + _x) / 2;
			}
			return _z;
		}
		if (_y > 0) return 1;
		return 0;
	}
}
