// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./BEP20.sol";

// Dice token with Governance.
contract DiceToken is BEP20 {

	constructor(string memory name, string memory symbol) public BEP20(name, symbol) {}

    /// @notice Creates _amount token to _to.
    function mint(address _to, uint256 _amount) external onlyOwner returns(bool) {
        _mint(_to, _amount);
        return true;
    }

	function burn(address _to, uint256 _amount) external onlyOwner {
		_burn(_to, _amount);
	}
}
