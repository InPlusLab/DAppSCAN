pragma solidity 0.4.24;

import "./DreamTokensVesting.sol";

contract TeamsAndTournamentOrganizersVesting is DreamTokensVesting {
    constructor(ERC20TokenInterface token, address withdraw) DreamTokensVesting(token, withdraw) public {} 
}