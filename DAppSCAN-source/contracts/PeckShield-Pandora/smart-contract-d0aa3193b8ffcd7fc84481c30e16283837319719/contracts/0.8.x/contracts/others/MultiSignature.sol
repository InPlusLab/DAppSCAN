//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract MultiSignature{
    using EnumerableSet for EnumerableSet.AddressSet;
    mapping(bytes32 => uint256) private confirmations;
    mapping(bytes32 => mapping(address => bool)) private isConfirmed;

    EnumerableSet.AddressSet private admins;
    uint256 public required;

    constructor(address _admin) {
        EnumerableSet.add(admins, _admin);
        required = 1;
    }

    /* ========== MODIFIER FUNCTIONS ========== */
    modifier onlyWallet() {
        require(msg.sender == address(this));
        _;
    }

    modifier onlyAdmin() {
        EnumerableSet.contains(admins, msg.sender);
        _;
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    function hashOperation(
        address _target,
        uint256 _value,
        bytes calldata _data,
        bytes32 _salt
    ) public pure virtual returns (bytes32 _hash) {
        return keccak256(abi.encode(_target, _value, _data, _salt));
    }

    function schedule(
        address _target,
        uint256 _value,
        bytes calldata _data,
        bytes32 _salt
    ) external onlyAdmin {
        bytes32 _id = hashOperation(_target, _value, _data, _salt);
        require(confirmations[_id] == 0, "MultiSign: operation already schedulted");
        _vote(_id, _target, _value, _data);
        emit Scheduled(_id, _target, _value, _data);
    }

    function vote(
        address _target,
        uint256 _value,
        bytes calldata _data,
        bytes32 _salt)
    external onlyAdmin {
        bytes32 _id = hashOperation(_target, _value, _data, _salt);
        require(isConfirm(_id, msg.sender) == false, "MultiSign: admin already voted");
        _vote(_id, _target, _value, _data);
        emit Voted(_id, _target, _value, _data);
    }

    function revoke(
        address _target,
        uint256 _value,
        bytes calldata _data,
        bytes32 _salt
    ) external onlyAdmin {
        bytes32 _id = hashOperation(_target, _value, _data, _salt);
        require(isConfirm(_id, msg.sender) == true, "MultiSign: admin haven't voted yet");
        isConfirmed[_id][msg.sender] = false;
        confirmations[_id]--;
        emit Revoked(_id, _target, _value, _data);
    }

    function getConfirmation(bytes32 _id) public view returns(uint256 _confirmation) {
        return confirmations[_id];
    }

    function isAdmin(address _account) public view returns (bool) {
        return EnumerableSet.contains(admins, _account);
    }

    function isConfirm(bytes32 _id, address _acc) public view returns(bool) {
        return isConfirmed[_id][_acc];
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _vote(
        bytes32 _id,
        address _target,
        uint256 _value,
        bytes calldata _data
    ) internal {
        confirmations[_id]++;
        isConfirmed[_id][msg.sender] = true;
        if (confirmations[_id] >= required) {
            (bool _success, ) = _target.call{value: _value}(_data);
            require(_success, "MultiSign: underlying transaction reverted");
            emit CallExecuted(_id, _target, _value, _data);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function addAdmin(address _newAdmin) external onlyWallet returns (bool) {
        require(_newAdmin != address(0), "MultiSign: _newAdmin is the zero address");
        return EnumerableSet.add(admins, _newAdmin);
    }

    function delAdmin(address _delAdmin) external onlyWallet returns (bool) {
        require(_delAdmin != address(0), "MultiSign: _delAdmin is the zero address");
        return EnumerableSet.remove(admins, _delAdmin);
    }

    function changeRequired(uint256 _newValue) external onlyWallet{
        require(_newValue > 0, "MultiSign: required = 0");
        required = _newValue;
    }

    /* ========== EVENTS ========== */

    event CallExecuted(bytes32 indexed id, address target, uint256 value, bytes data);
    event Voted(bytes32 indexed id, address target, uint256 value, bytes data);
    event Scheduled(bytes32 indexed id, address target, uint256 value, bytes data);
    event Revoked(bytes32 indexed id, address target, uint256 value, bytes data);
}