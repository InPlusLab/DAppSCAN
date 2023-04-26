// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20SnapshotUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

/**
 * @title COGI Token
 * @author COGI Inc
 */

contract CogiERC20 is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ERC20PausableUpgradeable,
    ERC20SnapshotUpgradeable,
    AccessControlEnumerableUpgradeable
{
    using SafeMathUpgradeable for uint256;

    bytes32 public constant MINTER_ROLE     = keccak256("MINTER_ROLE");
    bytes32 public constant FREEZE_ROLE     = keccak256("FREEZE_ROLE");
    uint256 private _maxSupply;
    uint256 private _supply;
    //mapping(address => uint256) private nonces;

    function initialize(string memory _name, string memory _symbol, uint256 __maxSupply) public virtual initializer {        
        __ERC20_init(_name, _symbol);
        __Ownable_init();
        
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _maxSupply = __maxSupply;
        _supply = 0;
    }


    function _mint(address account, uint256 amount) internal virtual override {
        require(_supply.add(amount) <= _maxSupply, "Over maxSupply");
        _supply = _supply.add(amount);
        super._mint(account, amount);
    }

    
    function mint(uint256 amount) public virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "Must have minter role to mint");
        _mint(_msgSender(), amount);
    }

    function addMinter(address account) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Must have admin role to addMinter");
        grantRole(MINTER_ROLE, account);
    }

    function removeMinter(address account) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "must have admin role to removeMinter");
        revokeRole(MINTER_ROLE, account);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20SnapshotUpgradeable) {
        require(!hasRole(FREEZE_ROLE, from), "Account temporarily unavailable.");
        super._beforeTokenTransfer(from, to, amount);
    }
}
