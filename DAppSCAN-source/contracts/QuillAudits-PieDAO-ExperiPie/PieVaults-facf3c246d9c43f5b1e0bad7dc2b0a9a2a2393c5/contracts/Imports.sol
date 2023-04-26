// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "diamond-2/contracts/facets/DiamondCutFacet.sol";
import "diamond-2/contracts/facets/DiamondLoupeFacet.sol";
import "diamond-2/contracts/facets/OwnershipFacet.sol";


// Get the compiler and typechain to pick up these facets
contract Imports {
    DiamondCutFacet public diamondCutFacet;
    DiamondLoupeFacet public diamondLoupeFacet;
    OwnershipFacet public ownershipFacet;
}