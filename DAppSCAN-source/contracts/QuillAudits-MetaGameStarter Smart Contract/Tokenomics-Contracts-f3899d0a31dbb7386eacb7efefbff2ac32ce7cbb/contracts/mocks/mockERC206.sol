pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract mockERC206 is ERC20 {

    constructor(string memory name, string memory symbol, uint256 supply) ERC20(name, symbol) {
        _mint(msg.sender, supply*10**6);
    }

    function decimals() override(ERC20) public pure returns(uint8) {
        return 6;
    }
}