pragma solidity 0.5.17;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

contract DloopAdmin {
    mapping(address => bool) private _adminMap;
    uint256 private _adminCount = 0;

    event AdminAdded(address indexed account);
    event AdminRenounced(address indexed account);

    constructor() public {
        _adminMap[msg.sender] = true;
        _adminCount = 1;
    }

    modifier onlyAdmin() {
        require(_adminMap[msg.sender], "caller does not have the admin role");
        _;
    }

    function numberOfAdmins() public view returns (uint256) {
        return _adminCount;
    }

    function isAdmin(address account) public view returns (bool) {
        return _adminMap[account];
    }

    function addAdmin(address account) public onlyAdmin {
        require(!_adminMap[account], "account already has admin role");
        require(account != address(0x0), "account must not be 0x0");
        _adminMap[account] = true;
        _adminCount = SafeMath.add(_adminCount, 1);
        emit AdminAdded(account);
    }

    function renounceAdmin() public onlyAdmin {
        _adminMap[msg.sender] = false;
        _adminCount = SafeMath.sub(_adminCount, 1);
        require(_adminCount > 0, "minimum one admin required");
        emit AdminRenounced(msg.sender);
    }
}
