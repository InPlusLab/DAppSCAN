pragma solidity ^0.5.7;
pragma experimental ABIEncoderV2;

import { MassetStructs } from "./MassetStructs.sol";

/**
 * @title   IBasketManager
 * @dev     (Internal) Interface for interacting with BasketManager
 *          VERSION: 1.0
 *          DATE:    2020-05-05
 */
contract IBasketManager is MassetStructs {
    function getBassets() external view returns (Basset[] memory bAssets, uint256 len);
}
