pragma solidity 0.5.11;

// interfaces
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DAIMock is ERC20Detailed, ERC20 {
  constructor()
    ERC20()
    ERC20Detailed('DAI', 'DAI', 18) public {
    _mint(address(this), 10**24); // 1.000.000 DAI
    _mint(msg.sender, 10**21); // 1.000 DAI
  }
}
