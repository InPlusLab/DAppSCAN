// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenAccessControl is Ownable {
	mapping(address => bool) public minters;
	mapping(address => bool) public whitelistedAddresses;

	bool public paused;
	bool public foreverUnpaused;
	bool public mintingDisabled;
	bool public whitelistDisabled;

	event MintersAdded(address[] minters);
	event MintersRemoved(address[] minters);
	event WhitelistedAddressesAdded(address[] minters);
	event WhitelistedAddressesRemoved(address[] minters);


	modifier notPaused() {
		require(!paused || (!whitelistDisabled && whitelistedAddresses[msg.sender]), "AccessControl: User cannot transfer");
		_;
	}

	modifier isMinter(address _caller) {
		require(!mintingDisabled, "AccessControl: Contract cannot mint tokens anymore");
		require(minters[_caller], "AccessControl: Cannot mint");
		_;
	}

	function disableWhitelist() external onlyOwner {
		require(!whitelistDisabled, "AccessControl: Whitelist already disabled");
		whitelistDisabled = true;
	}

	function changePauseStatus(bool _status) external onlyOwner {
		require(!foreverUnpaused, "AccessControl: Contract is unpaused forever");
		paused = _status;
	} 


	function disablePausingForever() external onlyOwner {
		require(!foreverUnpaused, "AccessControl: Contract is unpaused forever");
		foreverUnpaused = true;
		paused = false;
	}

	function addMinters(address[] calldata _minters) external onlyOwner {
		require(!mintingDisabled, "AccessControl: Contract cannot mint tokens anymore");

		for(uint256 i = 0; i < _minters.length; i++)
			minters[_minters[i]] = true;
		emit MintersAdded(_minters);
	}

	function removeMinters(address[] calldata _minters) external onlyOwner {
		require(!mintingDisabled, "AccessControl: Contract cannot mint tokens anymore");

		for(uint256 i = 0; i < _minters.length; i++)
			minters[_minters[i]] = false;
		emit MintersRemoved(_minters);
	}

	function addWhitelistedAddresses(address[] calldata _addresses) external onlyOwner {
		require(!whitelistDisabled, "AccessControl: Whitelist already disabled");

		for(uint256 i = 0; i < _addresses.length; i++)
			whitelistedAddresses[_addresses[i]] = true;
		emit WhitelistedAddressesAdded(_addresses);
	}

	function removeWhitelistedAddresses(address[] calldata _addresses) external onlyOwner {
		require(!whitelistDisabled, "AccessControl: Whitelist already disabled");

		for(uint256 i = 0; i < _addresses.length; i++)
			whitelistedAddresses[_addresses[i]] = false;
		emit WhitelistedAddressesRemoved(_addresses);
	}

	function disableMintingForever() external onlyOwner {
		require(!mintingDisabled, "AccessControl: Contract cannot mint anymore");
		mintingDisabled = true;
	}
}