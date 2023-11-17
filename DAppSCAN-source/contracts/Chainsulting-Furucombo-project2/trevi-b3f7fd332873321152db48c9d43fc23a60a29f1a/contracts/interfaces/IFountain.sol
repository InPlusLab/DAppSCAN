// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../libraries/interfaces/IERC20.sol";
import "../libraries/interfaces/IERC20Permit.sol";

interface IFountain is IERC20, IERC20Permit {
    // Getter
    function stakingToken() external view returns (address);
    function factory() external view returns (address);
    function archangel() external view returns (address);
    function joinedAngel(address user) external view returns (address[] memory);
    function angelInfo(address angel) external view returns (uint256, uint256);
    function joinTimeLimit(address owner, address sender) external view returns (uint256);
    function joinNonces(address owner) external view returns (uint256);
    function harvestTimeLimit(address owner, address sender) external view returns (uint256);
    function harvestNonces(address owner) external view returns (uint256);

    function setPoolId(uint256 pid) external;
    function deposit(uint256 amount) external;
    function depositTo(uint256 amount, address to) external;
    function withdraw(uint256 amount) external;
    function withdrawTo(uint256 amount, address to) external;
    function harvest(address angel) external;
    function harvestAll() external;
    function emergencyWithdraw() external;
    function joinAngel(address angel) external;
    function joinAngels(address[] calldata angels) external;
    function quitAngel(address angel) external;
    function quitAllAngel() external;
    function transferFromWithPermit(address owner,
        address recipient,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bool);

    function joinApprove(address sender, uint256 timeLimit) external returns (bool);
    function joinPermit(
        address user,
        address sender,
        uint256 timeLimit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function joinAngelFor(address angel, address user) external;
    function joinAngelsFor(address[] calldata angels, address user) external;
    function joinAngelForWithPermit(
        address angel,
        address user,
        uint256 timeLimit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function joinAngelsForWithPermit(
        address[] calldata angels,
        address user,
        uint256 timeLimit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function harvestApprove(address sender, uint256 timeLimit) external returns (bool);
    function harvestPermit(
        address owner,
        address sender,
        uint256 timeLimit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function harvestFrom(address angel, address from, address to) external;
    function harvestAllFrom(address from, address to) external;
    function harvestFromWithPermit(
        address angel,
        address from,
        address to,
        uint256 timeLimit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function harvestAllFromWithPermit(
        address from,
        address to,
        uint256 timeLimit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

}
