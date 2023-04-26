// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


interface IMetaERC20 is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address to, uint256 amount) external;
    function meta() external view returns (address meta);
    function assetId() external view returns (uint256 assetId);
    function data() external view returns (bytes memory data);
}