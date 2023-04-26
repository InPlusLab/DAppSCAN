// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.9;

import { IGovernable } from './IGovernable.sol';

import { IClearingHouseActions } from './clearinghouse/IClearingHouseActions.sol';
import { IClearingHouseCustomErrors } from './clearinghouse/IClearingHouseCustomErrors.sol';
import { IClearingHouseEnums } from './clearinghouse/IClearingHouseEnums.sol';
import { IClearingHouseEvents } from './clearinghouse/IClearingHouseEvents.sol';
import { IClearingHouseOwnerActions } from './clearinghouse/IClearingHouseOwnerActions.sol';
import { IClearingHouseStructures } from './clearinghouse/IClearingHouseStructures.sol';
import { IClearingHouseSystemActions } from './clearinghouse/IClearingHouseSystemActions.sol';
import { IClearingHouseView } from './clearinghouse/IClearingHouseView.sol';

interface IClearingHouse is
    IGovernable,
    IClearingHouseEnums,
    IClearingHouseStructures,
    IClearingHouseActions,
    IClearingHouseCustomErrors,
    IClearingHouseEvents,
    IClearingHouseOwnerActions,
    IClearingHouseSystemActions,
    IClearingHouseView
{}
