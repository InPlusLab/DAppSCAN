pragma solidity ^0.4.24;

import './RobotLiabilityAPI.sol';
import './LightContract.sol';

// Standard robot liability light contract
contract RobotLiability is RobotLiabilityAPI, LightContract {
    constructor(address _lib) public LightContract(_lib)
    { factory = LiabilityFactory(msg.sender); }
}
