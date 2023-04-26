// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GoGoToken is ERC20, Ownable {
	constructor() ERC20("GOGO Token", "GOGO") {
		_mint(owner(), 1000000 * (10**decimals()));
	}
}
