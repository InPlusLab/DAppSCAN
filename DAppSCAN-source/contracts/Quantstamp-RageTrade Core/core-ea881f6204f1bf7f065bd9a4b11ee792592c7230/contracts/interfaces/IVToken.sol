// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IVToken is IERC20 {
    function mint(address account, uint256 amount) external;

    function burn(uint256 amount) external;

    function setVPoolWrapper(address) external;
}
