// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "../libraries/NFTLib.sol";

interface IPandoBox is IERC721 {
    function create(address receiver, uint256 level) external returns(uint256);
    function burn(uint256 tokenId) external;
    function info(uint256 id) external view returns(NFTLib.Info memory);
}