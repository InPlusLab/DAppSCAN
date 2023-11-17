// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract LuckyToken is ERC20, Ownable {
    
    string private _name = "Lucky";
    string private _symbol = "LUCKY";
    
    uint256 private constant FAIR_LAUNCH = 1 * 1000000 * 10**18; //1 * 1000000 * 10**_decimals;
    uint256 private constant WAR_CHEST = 5 * 1000000 * 10**18;
    uint256 private constant ECOSYSTEM = 20 * 1000000 * 10**18;
    uint256 private constant CAP = 100 * 1000000 * 10**18; //max supply
    
    address Owner;
    address WarChest;
    address Ecosystem;

    constructor (address _Owner, address _Warchest, address _Ecosystem) ERC20(_name, _symbol) { 
        //set wallet address
        Owner = _Owner;
        WarChest = _Warchest;
        Ecosystem = _Ecosystem;

        //mint to Owner's Wallet for Fairlunch
        _mint(Owner, FAIR_LAUNCH);
        //mint to WarChest's Wallet
        _mint(WarChest, WAR_CHEST);
        //mint to Ecosystem's Wallet
        _mint(Ecosystem, ECOSYSTEM);
        //transfer to real owner
        transferOwnership(_Owner);
    }

    /**
     * @dev Returns the cap on the token's total supply.
     */
    function cap() public view virtual returns (uint256) {
        return CAP;
    }

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
    
    /**
     * @dev See {ERC20-_mint}.
     */
    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function _mint(address _to, uint256 _amount) internal virtual onlyOwner override {
        require(ERC20.totalSupply() + _amount <= cap(), "ERC20Capped: cap exceeded");
        super._mint(_to, _amount);
    }
}
