// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import { IERC20 } from "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


/* TODO: Actually methods are public instead of external */
interface YERC20 is IERC20 {
    function getPricePerFullShare() external view returns (uint256);

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _shares) external;
}
