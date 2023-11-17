pragma solidity ^0.4.15;

/**
 * Originally from https://github.com/TokenMarketNet/ico
 */

import "./ERC20.sol";

/**
 * A token that defines fractional units as decimals.
 */
contract FractionalERC20 is ERC20 {

  uint8 public decimals;

}