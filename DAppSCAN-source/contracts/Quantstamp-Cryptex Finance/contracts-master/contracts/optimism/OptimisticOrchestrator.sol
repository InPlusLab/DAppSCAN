// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "../IOrchestrator.sol";
import "./iOVM_CrossDomainMessenger.sol";

/**
 * @title TCAP Optimistic Orchestrator
 * @author Cryptex.finance
 * @notice Orchestrator contract in charge of managing the settings of the vaults, rewards and TCAP token. It acts as the owner of these contracts.
 */
contract OptimisticOrchestrator is IOrchestrator {
	/// @notice Address of the optimistic ovmL2CrossDomainMessenger contract.
	iOVM_CrossDomainMessenger public immutable ovmL2CrossDomainMessenger;

	/**
	 * @notice Constructor
	 * @param _guardian The guardian address
	 * @param _owner the owner of the contract
	 * @param _ovmL2CrossDomainMessenger address of the optimism ovmL2CrossDomainMessenger
	 */
	constructor(
		address _guardian,
		address _owner,
		address _ovmL2CrossDomainMessenger
	) IOrchestrator(_guardian, _owner) {
		require(
			_ovmL2CrossDomainMessenger != address(0),
			"OptimisticOrchestrator::constructor: address can't be zero"
		);
		ovmL2CrossDomainMessenger = iOVM_CrossDomainMessenger(_ovmL2CrossDomainMessenger);
	}

	// @notice Throws if called by an account different from the owner
	// @dev call needs to come from ovmL2CrossDomainMessenger
	modifier onlyOwner() override {
		require(
			msg.sender == address(ovmL2CrossDomainMessenger)
			&& ovmL2CrossDomainMessenger.xDomainMessageSender() == owner,
			"OptimisticOrchestrator: caller is not the owner"
		);
		_;
	}
}
