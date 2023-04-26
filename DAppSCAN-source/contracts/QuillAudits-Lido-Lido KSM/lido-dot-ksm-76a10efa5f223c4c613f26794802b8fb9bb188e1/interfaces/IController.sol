// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;


interface IController {
    function newSubAccount(uint16 index, bytes32 accountId, address paraAddress) external;

    function nominate(bytes32[] calldata _validators) external;

    function bond(bytes32 controller, uint256 amount) external;

    function bondExtra(uint256 amount) external;

    function unbond(uint256 amount) external;

    function withdrawUnbonded() external;

    function rebond(uint256 amount) external;

    function chill() external;

    function transferToParachain(uint256 amount) external;

    function transferToRelaychain(uint256 amount) external;
}
