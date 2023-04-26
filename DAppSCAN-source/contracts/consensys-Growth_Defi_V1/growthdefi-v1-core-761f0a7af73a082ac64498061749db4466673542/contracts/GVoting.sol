// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

/**
 * @dev An interface to extend gTokens with voting delegation capabilities.
 *      See GTokenType3.sol for further documentation.
 */
interface GVoting
{
	// view functions
	function votes(address _candidate) external view returns (uint256 _votes);
	function candidate(address _voter) external view returns (address _candidate);

	// open functions
	function setCandidate(address _newCandidate) external;

	// emitted events
	event ChangeCandidate(address indexed _voter, address indexed _oldCandidate, address indexed _newCandidate);
	event ChangeVotes(address indexed _candidate, uint256 _oldVotes, uint256 _newVotes);
}
