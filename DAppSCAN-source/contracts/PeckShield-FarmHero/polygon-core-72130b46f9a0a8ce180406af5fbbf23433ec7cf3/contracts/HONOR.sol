// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";


contract HONOR is ERC20BurnableUpgradeSafe, 
    OwnableUpgradeSafe {
    
    using SafeMath for uint256;

    mapping(address=>bool) _minters;

    modifier onlyMinter {
        
        require(_msgSender() == farmAddress());
        _;
    }

    function initialize(uint256 _init_supply) public initializer {

        OwnableUpgradeSafe.__Ownable_init();
        ERC20UpgradeSafe.__ERC20_init("HONOR","HONOR");
        ERC20BurnableUpgradeSafe.__ERC20Burnable_init();

        if(_init_supply > 0)
            _mint(msg.sender, _init_supply);

    }

    function setMinter(address _address, bool _can) public onlyOwner {
        _minters[_address] = _can;
    }

    function isMinter(address _address) external view returns (bool){
        return _minters[_address];
    }
    
    function mint(address _to, uint256 _amount) public onlyMinter {
        _mint(_to, _amount);
    }

    function farmAddress() public view returns (address) {
        return 0x8e5860DF653A467D1cC5b6160Dd340E8D475724E;
    }

}