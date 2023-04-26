pragma solidity ^0.4.24;

import './LiabilityFactory.sol';
import './XRT.sol';

contract LighthouseAPI {
    address[] public members;
    mapping(address => uint256) indexOf;

    mapping(address => uint256) public balances;

    uint256 public minimalFreeze;
    uint256 public timeoutBlocks;

    LiabilityFactory public factory;
    XRT              public xrt;

    uint256 public keepaliveBlock = 0;
    uint256 public marker = 0;
    uint256 public quota = 0;

    function quotaOf(address _member) public view returns (uint256)
    { return balances[_member] / minimalFreeze; }
}
