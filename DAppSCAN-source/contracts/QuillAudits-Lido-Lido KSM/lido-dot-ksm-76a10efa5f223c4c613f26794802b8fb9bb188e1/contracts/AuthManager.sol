// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../interfaces/IAuthManager.sol";


contract AuthManager is IAuthManager, Initializable {
    mapping(address => bytes32[])  internal members;
    uint256 internal constant NOTFOUND = type(uint256).max;
    bytes32 public constant SUPER_ROLE = keccak256("SUPER_ROLE");

    event AddMember(address member, bytes32 role);
    event RemoveMember(address member, bytes32 role);

    function initialize(address superior) external initializer {
        if (superior == address(0)) {
            members[msg.sender] = [SUPER_ROLE];
            emit AddMember(msg.sender, SUPER_ROLE);
        } else {
            members[superior] = [SUPER_ROLE];
            emit AddMember(msg.sender, SUPER_ROLE);
        }
    }

    function roles(address _member) external view returns (bytes32[] memory) {
        return members[_member];
    }

    function has(bytes32 role, address _member) external override view returns (bool) {
        return _find(members[_member], role) != NOTFOUND;
    }

    function add(bytes32 role, address member) external override {
        require(_find(members[msg.sender], SUPER_ROLE) != NOTFOUND, "FORBIDDEN");

        bytes32[] storage _roles = members[member];

        require(_find(_roles, role) == NOTFOUND, "ALREADY_MEMBER");
        _roles.push(role);
        emit AddMember(member, role);
    }

    function addByString(string calldata roleString, address member) external {
        require(_find(members[msg.sender], SUPER_ROLE) != NOTFOUND, "FORBIDDEN");

        bytes32[] storage _roles = members[member];
        bytes32 role = keccak256(bytes(roleString));

        require(_find(_roles, role) == NOTFOUND, "ALREADY_MEMBER");
        _roles.push(role);
        emit AddMember(member, role);
    }

    function remove(bytes32 role, address member) external override {
        require(_find(members[msg.sender], SUPER_ROLE) != NOTFOUND, "FORBIDDEN");
        require(msg.sender != member || role != SUPER_ROLE, "INVALID");

        bytes32[] storage _roles = members[member];

        uint256 i = _find(_roles, role);
        require(i != NOTFOUND, "MEMBER_NOT_FOUND");
        if (_roles.length == 1) {
            delete members[member];
        } else {
            if (i < _roles.length - 1) {
                _roles[i] = _roles[_roles.length - 1];
            }
            _roles.pop();
        }

        emit RemoveMember(member, role);
    }

    function _find(bytes32[] storage _roles, bytes32 _role) internal view returns (uint256) {
        for (uint256 i = 0; i < _roles.length; ++i) {
            if (_role == _roles[i]) {
                return i;
            }
        }
        return NOTFOUND;
    }

}
