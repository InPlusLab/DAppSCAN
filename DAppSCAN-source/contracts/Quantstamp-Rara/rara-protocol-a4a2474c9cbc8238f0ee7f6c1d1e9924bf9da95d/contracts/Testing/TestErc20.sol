//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/// @title TestErc20
/// @dev This contract implements the ERC20 standard and is used for unit testing purposes only
/// Anyone can mint tokens
contract TestErc20 is ERC20Upgradeable {
    /// @dev initializer to call after deployment, can only be called once
    function initialize(string memory name_, string memory symbol_)
        public
        initializer
    {
        __ERC20_init(name_, symbol_);
    }

    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }

    // 6 decimals to match USDC
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
