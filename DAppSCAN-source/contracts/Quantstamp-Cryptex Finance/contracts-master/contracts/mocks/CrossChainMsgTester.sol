// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "../polygon/PolygonL2Messenger.sol";

contract PolygonMsgTester {
	PolygonL2Messenger public immutable polygonMessenger;
	string public message;
	address public owner;

	modifier onlyOwner() {
		require(
			msg.sender == address(polygonMessenger)
			&& polygonMessenger.xDomainMessageSender() == owner,
			"caller is not the owner"
		);
		_;
	}

	constructor(address _owner, address _polygonMessenger) {
		require(
			_polygonMessenger != address(0),
			"Orchestrator::constructor: address can't be zero"
		);
		polygonMessenger = PolygonL2Messenger(_polygonMessenger);
		owner = _owner;
	}

	function setMessage(string memory _msg) external onlyOwner {
		message = _msg;
	}
}
