// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IActionPools {

    function getPoolInfo(uint256 _pid) external view 
        returns (address callFrom, uint256 callId, address rewardToken);
    function mintRewards(uint256 _callId) external;
    function getPoolIndex(address _callFrom, uint256 _callId) external view returns (uint256[] memory);

    function onAcionIn(uint256 _callId, address _account, uint256 _fromAmount, uint256 _toAmount) external;
    function onAcionOut(uint256 _callId, address _account, uint256 _fromAmount, uint256 _toAmount) external;
    function onAcionClaim(uint256 _callId, address _account) external;
    function onAcionEmergency(uint256 _callId, address _account) external;
    function onAcionUpdate(uint256 _callId) external;
}