pragma solidity ^0.5.2;

import "@openzeppelin/contracts/access/roles/WhitelistedRole.sol";


contract GlobalConfig is WhitelistedRole {
    // block delays when submiting withdrawal apllication to withdraw
    uint256 public withdrawalLockBlockCount;
    uint256 public brokerLockBlockCount;

    event CreateGlobalConfig();
    event UpdateGlobalParameter(bytes32 indexed key, uint256 value);

    constructor() public {
        emit CreateGlobalConfig();
    }

    function setGlobalParameter(bytes32 key, uint256 value) public onlyWhitelistAdmin {
        if (key == "withdrawalLockBlockCount") {
            withdrawalLockBlockCount = value;
        } else if (key == "brokerLockBlockCount") {
            brokerLockBlockCount = value;
        } else {
            revert("key not exists");
        }
        emit UpdateGlobalParameter(key, value);
    }
}
