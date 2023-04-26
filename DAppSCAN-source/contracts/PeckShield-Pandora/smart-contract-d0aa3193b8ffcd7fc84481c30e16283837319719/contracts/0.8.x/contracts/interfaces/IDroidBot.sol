// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "../libraries/NFTLib.sol";

interface IDroidBot is IERC721{
    function create(address, uint256, uint256) external returns(uint256);
    function upgrade(uint256, uint256, uint256) external;
    function burn(uint256) external;
    function info(uint256) external view returns(NFTLib.Info memory);
    function power(uint256) external view returns(uint256);
    function level(uint256) external view returns(uint256);
}