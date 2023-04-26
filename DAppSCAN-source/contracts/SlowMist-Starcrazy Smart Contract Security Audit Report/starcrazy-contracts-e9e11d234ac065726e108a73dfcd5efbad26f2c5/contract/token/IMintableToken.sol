pragma solidity <0.6.0 >=0.4.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IMintableToken is IERC20 {
    function mint(address, uint256) external returns (bool);

    function burn(uint256) external returns (bool);

    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
}
