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
*/

pragma solidity 0.8.7;

struct Point {
  int128 bias; // Voting weight
  int128 slope; // Multiplier factor to get voting weight at a given time
  uint256 timestamp;
  uint256 blockNumber;
}

interface IxALPACA {
  /// @dev Return the max epoch of the given "_user"
  function userPointEpoch(address _user) external view returns (uint256);

  /// @dev Return the max global epoch
  function epoch() external view returns (uint256);

  /// @dev Return the recorded point for _user at specific _epoch
  function userPointHistory(address _user, uint256 _epoch) external view returns (Point memory);

  /// @dev Return the recorded global point at specific _epoch
  function pointHistory(uint256 _epoch) external view returns (Point memory);

  /// @dev Trigger global check point
  function checkpoint() external;
}
