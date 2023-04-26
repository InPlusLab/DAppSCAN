// SPDX-License-Identifier: Unlicense
pragma solidity 0.5.17;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";

/**
 * @title BCUBE token contract
 * @notice Follows ERC-20 standards
 * @author Smit Rajput @ b-cube.ai
 **/

contract BCUBEToken is ERC20, ERC20Detailed, Ownable {
    /// @notice total supply cap of BCUBE tokens
    uint256 public cap;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 initialSupply,
        uint256 _cap
    ) public ERC20Detailed(_name, _symbol, _decimals) {
        require(_cap > 0, "ERC20Capped: cap is 0");
        cap = _cap;
        _mint(msg.sender, initialSupply);
    }

    /// @dev minting implementation for BCUBEs, intended to be called only once i.e. after private sale
    function mint(address account, uint256 amount) external onlyOwner {
        require(totalSupply().add(amount) <= cap, "ERC20Capped: cap exceeded");
        _mint(account, amount);
    }

    /// @dev only owner can burn tokens it already owns
    function burn(uint256 amount) external onlyOwner {
        _burn(owner(), amount);
    }
}
