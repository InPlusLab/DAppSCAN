// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.9;

import { Extsload } from '../utils/Extsload.sol';

contract ExtsloadTest is Extsload {
    constructor() {
        assembly {
            sstore(3, 9)
            sstore(4, 16)
            sstore(5, 25)
        }
    }
}
