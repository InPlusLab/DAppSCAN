// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { Proxied } from "../modules/proxy-factory/contracts/Proxied.sol";

/// @title A Maple implementation that is to be proxied, must extend MapleProxied.
contract MapleProxied is Proxied {}
