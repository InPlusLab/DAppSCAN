//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPAN is IERC20{
    function mint(address receiver, uint256 amount) external;
}