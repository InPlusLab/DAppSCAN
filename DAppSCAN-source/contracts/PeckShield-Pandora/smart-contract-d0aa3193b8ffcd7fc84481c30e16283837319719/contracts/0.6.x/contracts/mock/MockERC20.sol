pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        address to,
        uint256 supply
    ) public ERC20(name, symbol) {
        _mint(to, supply);
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}