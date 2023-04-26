// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { IVToken } from '../../interfaces/IVToken.sol';

contract VToken is ERC20, IVToken {
    address public vPoolWrapper;

    uint8 immutable _decimals;

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    constructor(
        string memory vTokenName,
        string memory vTokenSymbol,
        uint8 cTokenDecimals
    ) ERC20(vTokenName, vTokenSymbol) {
        _decimals = cTokenDecimals;
    }

    error Unauthorised();

    function setVPoolWrapper(address _vPoolWrapper) external {
        if (vPoolWrapper == address(0)) {
            vPoolWrapper = _vPoolWrapper;
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal view override {
        // transfer cases:
        // - vPoolWrapper mints tokens at uniswap pool address
        // - uniswap v3 pool transfers tokens to vPoolWrapper
        // - vPoolWrapper burns all tokens it has, at its own address
        if (!(from == address(0) || to == address(0) || from == vPoolWrapper || to == vPoolWrapper)) {
            revert Unauthorised();
        }
    }

    function mint(address receiver, uint256 amount) external {
        if (msg.sender != vPoolWrapper) {
            revert Unauthorised();
        }
        _mint(receiver, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
