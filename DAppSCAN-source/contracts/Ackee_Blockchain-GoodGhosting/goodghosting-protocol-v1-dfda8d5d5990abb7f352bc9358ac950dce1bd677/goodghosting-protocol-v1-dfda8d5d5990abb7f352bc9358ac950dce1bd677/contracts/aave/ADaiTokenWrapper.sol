// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract ATokenWrapper is ERC20 {

    constructor () ERC20('ATokenWrapper', 'ATokenWrapper') public {
    }

}