// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/AccessControl.sol";

contract DurationGuard is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    mapping(address => mapping(address => uint256)) public lastTx;
    mapping(bytes32 => uint256) public _durations;

    modifier onlyPerDuration(bytes32 role, address token) {
        require(
            block.timestamp - getLastClaimed(token) >= _durations[role],
            "DurationGuard: A duration has not passed from the last request"
        );
        _;

        lastTx[msg.sender][token] = block.timestamp;
    }

    function getLastClaimed(address token) public view returns (uint256) {
        return lastTx[msg.sender][token];
    }

    function setDuration(bytes32 _role, uint256 _duration) public {
        require(
            hasRole(ADMIN_ROLE, _msgSender()),
            "DurationGuard: ACCESS INVALID"
        );
        _durations[_role] = _duration;
    }
}
