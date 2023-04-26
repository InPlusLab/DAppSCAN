// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "../vaults/meter/interfaces/IERC20Minimal.sol";

import "./interfaces/IPrice.sol";

contract DexOracle is IPrice {
    address public pair;
    string public name;
    address public operator;
    uint256 public lastAskedBlock;
    address public from;
    address public to;
    int256 public prevPrice;
    
    constructor(address pair_, address from_, address to_, string memory name_) {
        pair = pair_;
        operator = msg.sender;
        name = name_;
    }

    function setPair(address pair_, address from_, address to_) public {
        require(msg.sender == operator, "IA");
        pair = pair_;
        from = from_;
        to = to_;
    }

    /**
     * Returns the latest price
     */
    function getThePrice() external view override returns (int256) {
        int256 fromP = int256(IERC20Minimal(from).balanceOf(pair) / 10 ** IERC20Minimal(from).decimals());
        int256 toP = int256(IERC20Minimal(to).balanceOf(pair) / 10 ** IERC20Minimal(to).decimals());
        int256 price = fromP == 0 ? int256(0) : 10**8 * toP / fromP;
        // Flashswap guard: if current block equals last asked block, return previous price, otherwise set prevPrice as the current price, set lastAskedBlock in current block
        require(lastAskedBlock < block.number, "DexOracle: FlashSwap detected"); 
        return price;
    }
}