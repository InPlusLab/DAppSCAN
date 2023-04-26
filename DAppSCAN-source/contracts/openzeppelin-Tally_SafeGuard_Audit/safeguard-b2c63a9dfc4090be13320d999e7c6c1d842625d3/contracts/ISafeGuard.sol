pragma solidity ^0.8.0;

/**
 * @dev External interface of SafeGuard declared to support ERC165 detection.
 */
interface ISafeGuard {
    function setTimelock(address _timelock) external;
    function queueTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external returns (bytes32);

    function cancelTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external;

    function executeTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external payable returns (bytes memory);

    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function __abdicate() external;
    function __queueSetTimelockPendingAdmin(address newPendingAdmin, uint eta) external;
    function __executeSetTimelockPendingAdmin(address newPendingAdmin, uint eta) external;
}
