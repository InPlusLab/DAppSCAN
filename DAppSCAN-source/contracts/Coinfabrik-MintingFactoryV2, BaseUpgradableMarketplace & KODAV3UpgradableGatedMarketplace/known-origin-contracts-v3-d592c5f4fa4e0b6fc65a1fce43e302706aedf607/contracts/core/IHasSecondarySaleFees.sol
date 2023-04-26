// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title Royalties formats required for use on the Rarible platform
/// @dev https://docs.rarible.com/asset/royalties-schema
interface IHasSecondarySaleFees is IERC165 {

    event SecondarySaleFees(uint256 tokenId, address[] recipients, uint[] bps);

    function getFeeRecipients(uint256 id) external returns (address payable[] memory);

    function getFeeBps(uint256 id) external returns (uint[] memory);
}
