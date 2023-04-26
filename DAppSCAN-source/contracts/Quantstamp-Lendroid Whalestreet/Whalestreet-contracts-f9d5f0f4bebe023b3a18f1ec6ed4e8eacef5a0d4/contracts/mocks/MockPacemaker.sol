// SPDX-License-Identifier: https://github.com/lendroidproject/protocol.2.0/blob/master/LICENSE.md
pragma solidity 0.7.4;


import "@openzeppelin/contracts/access/Ownable.sol";
import "../heartbeat/Pacemaker.sol";


contract MockPacemaker is Pacemaker, Ownable {}
