// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.8 <0.8.9;
// SWC-103-Floating Pragma: L2
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Cultos is ERC20, ERC20Burnable, ERC20Capped, Ownable {
    constructor()
        ERC20("Cultos", "CULTOS")
        ERC20Capped(1000000000 * (10**decimals()))
        ERC20Burnable()
    {
        _mint(msg.sender, 1000000000);
    }

    function _mint(address account, uint256 supply_)
        internal
        virtual
        override(ERC20, ERC20Capped)
        onlyOwner
    {
        super._mint(account, supply_ * (10**decimals()));
    }
}
