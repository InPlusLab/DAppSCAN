// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.6.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract MockERC20Mintable is ERC20 {

    constructor (string memory name, string memory symbol) public ERC20(name, symbol) { }

    /// @dev For the mock contract we don't really care for access control (i.e., make sure msg.sender has "onlyMinter" role)
    function mint(address account, uint256 amount) public returns (bool) {
        _mint(account, amount);
        return true;
    }
}