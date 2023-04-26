// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

interface IGovernable {
  event PendingGovernorSet(address pendingGovernor);
  event GovernorAccepted();

  function setPendingGovernor(address _pendingGovernor) external;

  function acceptGovernor() external;

  function governor() external view returns (address _governor);

  function pendingGovernor() external view returns (address _pendingGovernor);

  function isGovernor(address _account) external view returns (bool _isGovernor);
}
