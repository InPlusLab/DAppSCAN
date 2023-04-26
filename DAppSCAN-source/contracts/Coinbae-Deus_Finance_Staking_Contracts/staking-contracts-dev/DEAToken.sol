pragma solidity ^0.8.3;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.1/contracts/token/ERC20/ERC20.sol";

contract DEAToken is ERC20{
	constructor() public ERC20("DEA", "DEA") {
		_mint(msg.sender, 166670e18);	
	}
}