pragma solidity 0.5.16;
import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";

contract MockERC20 is ERC20, Ownable {
    string public name;
    string public symbol;
    uint8 public decimals = 18;

    constructor(string memory _name, string memory _symbol) public {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
