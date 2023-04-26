// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface ICollabFundsHandler {

    function init(address[] calldata _recipients, uint256[] calldata _splits) external;

    function totalRecipients() external view returns (uint256);

    function shareAtIndex(uint256 index) external view returns (address _recipient, uint256 _split);
}
