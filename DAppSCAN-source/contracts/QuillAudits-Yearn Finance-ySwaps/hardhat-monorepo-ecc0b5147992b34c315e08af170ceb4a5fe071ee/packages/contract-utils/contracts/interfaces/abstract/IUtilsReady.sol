// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '../utils/IGovernable.sol';
import '../utils/ICollectableDust.sol';
import '../utils/IPausable.sol';

interface IUtilsReady is IGovernable, ICollectableDust, IPausable {}
