// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;
pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPAN is IERC20{
    function mint(address, uint256) external;
}
