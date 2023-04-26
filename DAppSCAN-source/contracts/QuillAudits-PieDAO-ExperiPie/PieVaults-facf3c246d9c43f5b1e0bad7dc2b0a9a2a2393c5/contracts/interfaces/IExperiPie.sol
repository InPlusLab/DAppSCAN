// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "diamond-2/contracts/interfaces/IERC173.sol";
import "./IBasketFacet.sol";
import "./IERC20Facet.sol";
import "./ICallFacet.sol";

/**
    @title ExperiPie Interface
    @dev Combines all ExperiPie facet interfaces into one
*/
interface IExperiPie is IERC20, IBasketFacet, IERC20Facet, IERC173, ICallFacet {
}