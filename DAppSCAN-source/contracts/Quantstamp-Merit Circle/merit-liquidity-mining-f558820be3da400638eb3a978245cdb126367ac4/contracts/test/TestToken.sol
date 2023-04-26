// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        //silence
    }

    function mint(address _receiver, uint256 _amount) external {
        _mint(_receiver, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        _burn(_from, _amount);
    }
}