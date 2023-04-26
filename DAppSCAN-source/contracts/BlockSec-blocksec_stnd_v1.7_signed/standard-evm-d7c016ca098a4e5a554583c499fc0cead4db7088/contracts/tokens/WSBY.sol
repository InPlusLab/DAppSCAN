// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract WSBY0 is AccessControl, ERC20 {
    // Create a new role identifier for the minter role
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC20("Wrapped Shibuya", "WSBY") {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MINTER_ROLE, _msgSender());
    }

    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(super.balanceOf(msg.sender) >= wad);
        _burn(msg.sender, wad);
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function mint(address to, uint256 amount) external {
        // Check that the calling account has the minter role
        require(
            hasRole(MINTER_ROLE, msg.sender),
            "Wrapped Shibuya: Caller is not a minter"
        );
        _mint(to, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(
            currentAllowance >= amount,
            "ERC20: burn amount exceeds allowance"
        );
        _approve(account, _msgSender(), currentAllowance - amount);
        _burn(account, amount);
    }
}
