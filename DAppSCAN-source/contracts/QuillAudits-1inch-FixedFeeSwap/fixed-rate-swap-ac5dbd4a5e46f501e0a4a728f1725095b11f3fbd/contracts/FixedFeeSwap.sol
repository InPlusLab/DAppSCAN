// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract FixedFeeSwap is ERC20, Ownable {
    using SafeERC20 for IERC20;

    IERC20 immutable public token0;
    IERC20 immutable public token1;
    uint256 immutable public amountMultiplier;

    uint8 immutable private _decimals;

    // SWC-131-Presence of unused variables: L21 -L21
    uint256 constant private _DIRECTION_MASK = 1 << 255;
    uint256 constant private _AMOUNT_MASK = ~_DIRECTION_MASK;
    uint256 constant private _FEE_SCALE = 1e18;

    constructor(
        IERC20 _token0,
        IERC20 _token1,
        uint256 _fee,
        string memory name,
        string memory symbol,
        uint8 decimals_
    )
        ERC20(name, symbol)
    {
        require(_fee < _FEE_SCALE, "Fee should be < 1");
        require(_fee > 0, "Fee should be > 0");

        amountMultiplier = _FEE_SCALE - _fee;
        token0 = _token0;
        token1 = _token1;
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns(uint8) {
        return _decimals;
    }

    function getReturn(uint256 inputAmount) public view returns(uint256 outputAmount) {
        outputAmount = inputAmount * amountMultiplier / _FEE_SCALE;
    }

    function deposit(uint256 token0Amount, uint256 token1Amount) external returns(uint256 share) {
        share = depositFor(token0Amount, token1Amount, msg.sender);
    }

    function depositFor(uint256 token0Amount, uint256 token1Amount, address to) public onlyOwner returns(uint256 share) {
        uint256 inputAmount = token0Amount + token1Amount;
        require(inputAmount > 0, "Empty deposit is not allowed");

        uint256 _totalSupply = totalSupply();
        share = inputAmount;
        if (_totalSupply > 0) {
            uint256 totalBalance = token0.balanceOf(address(this)) + token1.balanceOf(address(this));
            share = inputAmount * _totalSupply / totalBalance;
        }

        if (token0Amount > 0) {
            token0.safeTransferFrom(msg.sender, address(this), token0Amount);
        }
        if (token1Amount > 0) {
            token1.safeTransferFrom(msg.sender, address(this), token1Amount);
        }
        _mint(to, share);
    }

    function withdraw(uint256 amount) external returns(uint256 token0Share, uint256 token1Share) {
        (token0Share, token1Share) = withdrawFor(amount, msg.sender);
    }

    function withdrawFor(uint256 amount, address to) public returns(uint256 token0Share, uint256 token1Share) {
        require(amount > 0, "Empty withdrawal is not allowed");

        uint256 _totalSupply = totalSupply();
        token0Share = token0.balanceOf(address(this)) * amount / _totalSupply;
        token1Share = token1.balanceOf(address(this)) * amount / _totalSupply;

        _burn(msg.sender, amount);
        if (token0Share > 0) {
            token0.safeTransfer(to, token0Share);
        }
        if (token1Share > 0) {
            token1.safeTransfer(to, token1Share);
        }
    }

    function swap0To1(uint256 inputAmount) external returns(uint256 outputAmount) {
        outputAmount = swap0To1For(inputAmount, msg.sender);
    }

    function swap1To0(uint256 inputAmount) external returns(uint256 outputAmount) {
        outputAmount = swap1To0For(inputAmount, msg.sender);
    }

    function swap0To1For(uint256 inputAmount, address to) public returns(uint256 outputAmount) {
        return _swap(token0, token1, inputAmount, to);
    }

    function swap1To0For(uint256 inputAmount, address to) public returns(uint256 outputAmount) {
        return _swap(token1, token0, inputAmount, to);
    }

    function _swap(IERC20 tokenFrom, IERC20 tokenTo, uint256 inputAmount, address to) private returns(uint256 outputAmount) {
        outputAmount = getReturn(inputAmount);
        require(outputAmount > 0, "Empty swap is not allowed");
        tokenFrom.safeTransferFrom(msg.sender, address(this), inputAmount);
        tokenTo.safeTransfer(to, outputAmount);
    }
}
