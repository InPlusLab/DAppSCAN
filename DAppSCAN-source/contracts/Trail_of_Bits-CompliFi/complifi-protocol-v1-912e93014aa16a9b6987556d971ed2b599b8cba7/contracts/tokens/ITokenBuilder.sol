// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./IERC20MintedBurnable.sol";
import "../IDerivativeSpecification.sol";

interface ITokenBuilder {
    function isTokenBuilder() external pure returns (bool);

    function buildTokens(
        IDerivativeSpecification derivative,
        uint256 settlement,
        address _collateralToken
    ) external returns (IERC20MintedBurnable, IERC20MintedBurnable);
}
