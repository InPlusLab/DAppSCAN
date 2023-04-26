// SPDX-License-Identifier: MIT

pragma solidity ^0.6.6;

import {
    OwnableUpgradeSafe
} from "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

import {
    ERC20PausableUpgradeSafe
} from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Pausable.sol";

contract FakeInvestmentToken is OwnableUpgradeSafe, ERC20PausableUpgradeSafe {
    function initialize(string memory name, string memory symbol)
        public
        initializer
    {
        __Ownable_init();
        __ERC20_init(name, symbol);
        __ERC20Pausable_init();
    }

    // functions used in rebalances
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    // pausable functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
