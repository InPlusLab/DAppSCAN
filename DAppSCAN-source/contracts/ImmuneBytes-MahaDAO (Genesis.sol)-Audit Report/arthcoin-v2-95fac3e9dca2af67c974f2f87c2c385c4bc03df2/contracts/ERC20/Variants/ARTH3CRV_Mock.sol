// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '../ERC20.sol';

contract ARTH3CRV_Mock is ERC20 {
    constructor() ERC20('Curve.fi Factory USD Metapool: Arth', 'ARTH3CRV-f') {}
}
