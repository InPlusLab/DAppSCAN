// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "../IOrchestrator.sol";
import "./PolygonL2Messenger.sol";

/**
 * @title TCAP Polygon Orchestrator
 * @author Cryptex.finance
 * @notice Orchestrator contract in charge of managing the settings of the vaults, rewards and TCAP token. It acts as the owner of these contracts.
 */
contract PolygonOrchestrator is IOrchestrator {
	/// @notice Address of the polygonMessenger contract.
	PolygonL2Messenger public polygonMessenger;

	/// @notice event emitted when polygonMessenger is updated.
	event UpdatedPolygonMessenger(
		PolygonL2Messenger oldPolygonMessenger,
		PolygonL2Messenger newPolygonMessenger
	);

	// @notice Throws if called by an account different from the owner
	// @dev call needs to come from polygonMessenger
	modifier onlyOwner() override {
		require(
			msg.sender == address(polygonMessenger)
			&& polygonMessenger.xDomainMessageSender() == owner
		);
		_;
	}

	/**
	 * @notice Constructor
	 * @param _guardian The guardian address
	**/
	constructor(
		address _guardian,
		address _owner,
		address _polygonMessenger
	) IOrchestrator(_guardian, _owner){
		require(
			_polygonMessenger != address(0),
			"PolygonOrchestrator::constructor: address can't be zero"
		);
		polygonMessenger = PolygonL2Messenger(_polygonMessenger);
	}

	/**
	 * @notice updates the polygonMessenger instance
	 * @param newPolygonMessenger address of the new PolygonL2Messenger contract
	**/
	function updatePolygonMessenger(address newPolygonMessenger) external onlyOwner {
		require(
			newPolygonMessenger != address (0),
			"PolygonOrchestrator: new owner is the zero address"
		);
		emit UpdatedPolygonMessenger(polygonMessenger, PolygonL2Messenger(newPolygonMessenger));
		polygonMessenger = PolygonL2Messenger(newPolygonMessenger);
	}
}
