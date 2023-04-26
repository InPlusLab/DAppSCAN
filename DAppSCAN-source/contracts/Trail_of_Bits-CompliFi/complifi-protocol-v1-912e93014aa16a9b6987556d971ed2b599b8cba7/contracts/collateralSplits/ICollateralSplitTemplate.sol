// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

interface ICollateralSplitTemplate {
    function splitNominalValue(int256 _normalizedValue)
        external
        pure
        returns (int256);

    function normalize(int256 _u_0, int256 _u_T) external pure returns (int256);

    function range(int256 _split) external returns (uint256);
}
