// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';

interface IPositionManager {
    struct ModuleInfo {
        bool isActive;
        bytes32 data;
    }

    struct AaveReserve {
        mapping(uint256 => uint256) positionShares;
        mapping(uint256 => uint256) tokenIds;
        uint256 sharesEmitted;
    }

    function toggleModule(
        uint256 tokenId,
        address moduleAddress,
        bool activated
    ) external;

    function setModuleData(
        uint256 tokenId,
        address moduleAddress,
        bytes32 data
    ) external;

    function getModuleInfo(uint256 _tokenId, address _moduleAddress)
        external
        view
        returns (bool isActive, bytes32 data);

    function withdrawERC20(address tokenAddress) external;

    function middlewareDeposit(uint256 tokenId) external;

    function getAllUniPositions() external view returns (uint256[] memory);

    function pushPositionId(uint256 tokenId) external;

    function removePositionId(uint256 index) external;

    function pushTokenIdToAave(
        address token,
        uint256 id,
        uint256 tokenId
    ) external;

    function getTokenIdFromAavePosition(address token, uint256 id) external view returns (uint256 tokenId);

    function getOwner() external view returns (address);
}
