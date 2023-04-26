// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../IStableSwap3Pool.sol";

contract MockStableSwap3Pool is IStableSwap3Pool {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    // DAI, USDC, USDT
    uint[3] public RATE = [10020, 9995, 9990];
    uint[3] public PRECISION_MUL = [1, 1000000000000, 1000000000000];

    IERC20[3] public inputTokens; // DAI, USDC, USDT
    IERC20 public token3CRV; // 3Crv

    constructor (IERC20 _tokenDAI, IERC20 _tokenUSDC, IERC20 _tokenUSDT, IERC20 _token3CRV) public {
        inputTokens[0] = _tokenDAI;
        inputTokens[1] = _tokenUSDC;
        inputTokens[2] = _tokenUSDT;
        token3CRV = _token3CRV;
    }

    function get_virtual_price() external override view returns (uint) {
        return RATE[0].add(RATE[1]).add(RATE[2]).mul(1e18).div(30000);
    }

    function balances(uint _index) external override view returns (uint) {
        return inputTokens[_index].balanceOf(address(this));
    }

    function get_dy(int128 i, int128 j, uint dx) public override view returns (uint) {
        return dx.mul(RATE[uint8(i)]).mul(PRECISION_MUL[uint8(i)]).div(RATE[uint8(j)]).div(PRECISION_MUL[uint8(j)]);
    }

    function exchange(int128 i, int128 j, uint dx, uint min_dy) external override {
        uint dy = get_dy(i, j, dx);
        require(dy >= min_dy, "below min_dy");
        inputTokens[uint8(i)].safeTransferFrom(msg.sender, address(this), dx);
        inputTokens[uint8(j)].safeTransfer(msg.sender, dy);
    }

    function add_liquidity(uint[3] calldata amounts, uint min_mint_amount) external override {
        uint _shareAmount = 0;
        for (uint8 i = 0; i < 3; ++i) {
            _shareAmount = _shareAmount.add(amounts[i].mul(RATE[i]).mul(PRECISION_MUL[i]).div(10000));
        }
        require(_shareAmount >= min_mint_amount, "below min_mint_amount");
        token3CRV.safeTransfer(msg.sender, _shareAmount);
    }

    function remove_liquidity(uint, uint[3] calldata) external override {
        require(false, "Not implemented");
    }

    function remove_liquidity_one_coin(uint _token_amount, int128 i, uint min_amount) external override {
        uint _outputAmount = calc_withdraw_one_coin(_token_amount, i);
        require(_outputAmount >= min_amount, "below min_amount");
        token3CRV.safeTransferFrom(msg.sender, address(this), _token_amount);
        inputTokens[uint8(i)].safeTransfer(msg.sender, _outputAmount);
    }

    function calc_token_amount(uint[3] calldata amounts, bool) public override view returns (uint) {
        uint _shareAmount = 0;
        for (uint8 i = 0; i < 3; ++i) {
            _shareAmount = _shareAmount.add(amounts[i].mul(RATE[i]).mul(PRECISION_MUL[i]).div(10000));
        }
        return _shareAmount;
    }

    function calc_withdraw_one_coin(uint _token_amount, int128 i) public override view returns (uint) {
        return _token_amount.mul(10000).div(RATE[uint8(i)]).div(PRECISION_MUL[uint8(i)]);
    }
}
