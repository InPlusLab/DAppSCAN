// SPDX-License-Identifier: MIT
/**
  ∩~~~~∩ 
  ξ ･×･ ξ 
  ξ　~　ξ 
  ξ　　 ξ 
  ξ　　 “~～~～〇 
  ξ　　　　　　 ξ 
  ξ ξ ξ~～~ξ ξ ξ 
　 ξ_ξξ_ξ　ξ_ξξ_ξ
Alpaca Fin Corporation
**/

pragma solidity 0.8.7;

import "./interfaces/IGrassHouse.sol";

/// @title GrassHouseGateway
contract GrassHouseGateway {
  function claimMultiple(address[] calldata _grassHouses, address _for) external {
    for (uint256 i = 0; i < _grassHouses.length; i++) {
      IGrassHouse(_grassHouses[i]).claim(_for);
    }
  }
}
