// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface IBurnableERC20 is IERC20 {
    function mint(address account, uint256 amount) external;

    function burn(uint256 amount) external;
}