// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../Dependencies/IERC20.sol";
import "../Dependencies/IERC2612.sol";

interface IATIDToken is IERC20, IERC2612 { 
   
    // --- Events ---
    
    event CommunityIssuanceAddressSet(address _communityIssuanceAddress);
    event ATIDStakingAddressSet(address _atidStakingAddress);
    event LockupContractFactoryAddressSet(address _lockupContractFactoryAddress);

    // --- Functions ---
    
    function sendToATIDStaking(address _sender, uint256 _amount) external;

    function getDeploymentStartTime() external view returns (uint256);
}
