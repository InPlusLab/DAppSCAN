// SPDX-License-Identifier: MIT
// solhint-disable func-name-mixedcase
// solhint-disable var-name-mixedcase

pragma solidity 0.6.12;

interface IConverter {
    function token() external returns (address _share);
    function convert(
        address _input,
        address _output,
        uint _inputAmount
    ) external returns (uint _outputAmount);
    function convert_rate(
        address _input,
        address _output,
        uint _inputAmount
    ) external view returns (uint _outputAmount);
    function convert_stables(
        uint[3] calldata amounts
    ) external returns (uint _shareAmount); // 0: DAI, 1: USDC, 2: USDT
    function get_dy(int128 i, int128 j, uint dx) external view returns (uint);
    function exchange(int128 i, int128 j, uint dx, uint min_dy) external returns (uint dy);
    function calc_token_amount(
        uint[3] calldata amounts,
        bool deposit
    ) external view returns (uint _shareAmount);
    function calc_token_amount_withdraw(
        uint _shares,
        address _output
    ) external view returns (uint _outputAmount);
}
