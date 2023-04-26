// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract MockTetherToken is ERC20, Ownable {
    uint256 tokenSupply = 10000000000 * (10**18); // 100K

    address public governance;

    mapping(address => bool) public minters;

    modifier onlyGovernance() {
        require(msg.sender == governance, "!governance");
        _;
    }

    event RecoverToken(address indexed token, address indexed destination, uint256 indexed amount);

    constructor() ERC20("Tether", "USDT") {
        governance = msg.sender;
        _mint(governance, tokenSupply);
    }

    function setGovernance(address _governance) public onlyGovernance {
        governance = _governance;
    }

    function recoverToken(
        address token,
        address destination,
        uint256 amount
    ) external onlyOwner {
        require(token != destination, "Invalid address");
        require(IERC20(token).transfer(destination, amount), "Retrieve failed");
        emit RecoverToken(token, destination, amount);
    }
}
