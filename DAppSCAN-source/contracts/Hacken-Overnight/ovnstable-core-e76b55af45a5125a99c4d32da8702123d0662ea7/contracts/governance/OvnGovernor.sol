// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/compatibility/GovernorCompatibilityBravo.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";

contract OvnGovernor is Governor, GovernorSettings, GovernorCompatibilityBravo, GovernorVotes, GovernorVotesQuorumFraction, GovernorTimelockControl {
    constructor(ERC20Votes _token, TimelockController _timelock)
    Governor("OvnGovernor")
    GovernorSettings(1 /* 1 block */, 200 /* 2 minute */, 0)
    GovernorVotes(_token)
    GovernorVotesQuorumFraction(75)
    GovernorTimelockControl(_timelock)
    {}


    uint256[] private _proposalsIds;

    function getProposals() public view returns (uint256[] memory){
        return _proposalsIds;
    }


    function quorum(uint256 blockNumber)
    public
    view
    override(IGovernor, GovernorVotesQuorumFraction)
    returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function getVotes(address account, uint256 blockNumber)
    public
    view
    override(IGovernor, GovernorVotes)
    returns (uint256)
    {
        return super.getVotes(account, blockNumber);
    }

    function state(uint256 proposalId)
    public
    view
    override(Governor, IGovernor, GovernorTimelockControl)
    returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposeExec(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    public
    returns (uint256)
    {
        uint256 id = super.propose(targets, values, calldatas, description);
        _proposalsIds.push(id);
        return id;
    }

    function propose(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    public
    override(Governor, GovernorCompatibilityBravo, IGovernor)
    returns (uint256)
    {
        return super.propose(targets, values, calldatas, description);
    }

    function proposalThreshold()
    public
    view
    override(Governor, GovernorSettings)
    returns (uint256)
    {
        return super.proposalThreshold();
    }

    function _execute(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
    internal
    override(Governor, GovernorTimelockControl)
    {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
    internal
    override(Governor, GovernorTimelockControl)
    returns (uint256)
    {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function voteSucceeded(uint256 proposalId) public view returns (bool){
        return super._voteSucceeded(proposalId);
    }

    function quorumReached(uint256 proposalId) public view returns (bool){
        return super._quorumReached(proposalId);
    }

    function queueExec(uint256 proposalId) public {
        return super.queue(proposalId);
    }

    function executeExec(uint256 proposalId) public {
        super.execute(proposalId);
    }

    function _executor()
    internal
    view
    override(Governor, GovernorTimelockControl)
    returns (address)
    {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId)
    public
    view
    override(Governor, IERC165, GovernorTimelockControl)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
