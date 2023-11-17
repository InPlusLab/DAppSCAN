// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20} from '../ERC20/ERC20.sol';

/**
 * @title  MahaToken.
 * @author Steven Enamake.
 */
contract MahaToken is ERC20 {
    address public upgradedAddress;
    bool public deprecated;
    string public contactInformation = 'contact@mahadao.com';
    string public reason;
    string public link = 'https://mahadao.com';
    string public url = 'https://mahadao.com';
    string public website = 'https://mahadao.io';

    constructor() ERC20('MahaDAO', 'MAHA') {
        _mint(msg.sender, 10000000000000e18); // For testing purposes.
    }
}
