//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ICurvePoolUnderlying {
    function add_liquidity(
        uint256[3] memory amounts,
        uint256 minMintAmount,
        bool useUnderlying
    ) external returns (uint256);

    function remove_liquidity(
        uint256 burnAmount,
        uint256[3] memory minAmounts,
        bool useUnderlying
    ) external returns (uint256[3] memory);

    function exchange(
        int128 i,
        int128 j,
        uint256 input,
        uint256 minOutput
    ) external returns (uint256);

    function calc_token_amount(uint256[3] memory amounts, bool isDeposit)
        external
        view
        returns (uint256);

    function get_virtual_price() external view returns (uint256);
}
